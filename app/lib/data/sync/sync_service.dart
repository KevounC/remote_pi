// SyncService is the single app-side transcript writer.
//
// Consumes the channel (ConnectionManager status + PeerChannel serverMessages),
// appends canonical TranscriptEvent records, and materializes the disposable
// row-granular `msgs` Hive projection read by repositories/UI. The `msgs` box
// is not transcript truth and can be rebuilt from the event store.
//
// Streaming remains in-memory for UI responsiveness; AgentChunk deltas are
// also event-store inputs, and finalized/projection rows are derived from the
// stored event log.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/local/transcript_event_store_hive.dart';
import 'package:app/data/sync/session_history_replay.dart';
import 'package:app/data/sync/sync_events.dart';
import 'package:app/data/sync/session_gate.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:flutter/foundation.dart';

class SyncService extends Service {
  final ConnectionManager _conn;
  final LocalBoxes _boxes;
  final TranscriptEventStore _eventStore;
  final SessionGate _sessionGate = const SessionGate();

  StreamSubscription<ConnectionStatus>? _connSub;
  StreamSubscription<ServerMessage>? _msgSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<Map<String, PresenceState>>? _presenceSub;

  // Active session being written (follows ConnectionManager). Persistence is
  // bound to [_activeRef]; [_activeEpk]/[_activeRoomId] remain available for
  // room-scoped reachability/runtime while the canonical session id is unknown.
  String? _activeEpk;
  String _activeRoomId = 'main';
  RemoteSessionRef? _activeRef;

  // Highest `session_started_at` ever accepted for this active session.
  // Any incoming SessionHistory with a lower value is stale and rejected.
  int? _acceptedSessionStartedAtHighWater;

  // In-memory dedupe + ordering for the active session's msgs box. Rebuilt on
  // [activate]. Key = `<role>:<id>` so a user msg and the assistant reply that
  // shares its id don't collide.
  final Map<String, int> _idToSeq = {};
  int _nextSeq = 0;
  bool _indexLoaded = false;

  // Serialise box mutations so concurrent async writes stay ordered.
  Future<void> _writeChain = Future<void>.value();

  // Streaming — in-memory only (#7).
  final StringBuffer _chunkBuffer = StringBuffer();
  Timer? _flushTimer;
  StreamingMessage? _streaming;
  final StreamController<StreamingMessage?> _streamingController =
      StreamController<StreamingMessage?>.broadcast();

  final StreamController<SessionEvent> _eventController =
      StreamController<SessionEvent>.broadcast();

  String? _queuedText;
  final StreamController<String?> _queuedController =
      StreamController<String?>.broadcast();

  bool _pendingSyncRequest = false;
  Timer? _syncDebounce;

  // Active-room turn projection derived from transcript events and local
  // optimistic send state. This is the single in-memory source for chat
  // working/cancel state; legacy boolean getters below derive from it.
  TranscriptTurnView _turnView = TranscriptTurnView.idle;
  final StreamController<TranscriptTurnView> _turnViewController =
      StreamController<TranscriptTurnView>.broadcast();

  // Plan/32 safety net — if the relay never echoes a sent message back, the
  // optimistic `pending:true` bubble would spin forever. After this window we
  // replace the bubble with a visible failure row. The real delivery fix lives
  // in the relay/Pi path; this is the app-side backstop. Per-message (`id`)
  // timers are cancelled on echo, user-cancel, session switch, and dispose.
  final Duration pendingSendTimeout;
  final Map<String, Timer> _pendingSendTimers = {};

  SyncService(
    this._conn,
    this._boxes, {
    TranscriptEventStore? transcriptEventStore,
    this.pendingSendTimeout = const Duration(seconds: 20),
  }) : _eventStore = transcriptEventStore ?? HiveTranscriptEventStore(_boxes) {
    _connSub = _conn.statusStream.listen(_onStatus);
    _roomsSub = _conn.roomsStream.listen((_) => _onRoomsChanged());
    _presenceSub = _conn.presenceStream.listen((_) => _writeRuntime());
    _onStatus(_conn.status); // replay current
  }

  // ---------------------------------------------------------------------------
  // Public surface (commands + in-memory streams)
  // ---------------------------------------------------------------------------

  StreamingMessage? get streaming => _streaming;
  Stream<StreamingMessage?> get streamingStream => _streamingController.stream;
  Stream<SessionEvent> get events => _eventController.stream;
  String? get queuedText => _queuedText;
  Stream<String?> get queuedStream => _queuedController.stream;

  TranscriptTurnView get turnView => _turnView;
  Stream<TranscriptTurnView> get turnViewStream => _turnViewController.stream;
  AppTurnProjection get turnProjection => _turnView.toAppProjection();
  Stream<AppTurnProjection> get turnProjectionStream =>
      _turnViewController.stream.map((turn) => turn.toAppProjection());

  /// Compatibility getters. They are derived from [_turnView], never written as
  /// independent mutable booleans/ids.
  bool get isWorking => turnProjection.working;
  Stream<bool> get workingStream =>
      turnProjectionStream.map((projection) => projection.working).distinct();

  /// `cancel` target for the in-flight reply (null when idle).
  String? get workingReplyTo => turnProjection.cancelTargetId;

  String? get activeEpk => _activeEpk;
  String get activeRoomId => _activeRoomId;
  RemoteSessionRef? get activeSessionRef => _activeRef;

  RemoteSessionRef? _resolveActiveRef(String epk, String roomId) {
    final activePeer = _conn.activePeer;
    if (activePeer == null || activePeer.remoteEpk != epk) return null;
    if (_conn.activeRoomId != roomId) return null;
    final sessionId = _conn.activeSessionId;
    if (sessionId == null || sessionId.isEmpty) return null;
    return RemoteSessionRef(peerEpk: epk, roomId: roomId, sessionId: sessionId);
  }

  bool _isStillActive(RemoteSessionRef ref) => _activeRef == ref;

  /// Bind the writer to a canonical remote session. The `(peer, room)` pair
  /// may be known before the Pi reports a `session_id`; in that state runtime
  /// reachability can still update, but transcript persistence waits for the
  /// full [RemoteSessionRef].
  Future<void> activate(String epk, String roomId) async {
    final room = roomId.isEmpty ? 'main' : roomId;
    final nextRef = _resolveActiveRef(epk, room);
    final sameRoom = _activeEpk == epk && _activeRoomId == room;
    final sameRef = _activeRef == nextRef;
    if (sameRoom && sameRef && _indexLoaded) return;

    // Genuine session switch or session-id rotation: drop in-memory turn state
    // and projection buffers so the previous canonical transcript cannot bleed
    // into the newly active session-scoped box. We deliberately do NOT clear
    // the previous durable session index — the prior Pi session may still be
    // visible via room-level relay metadata.
    _resetTurnState(clearPendingSendTimers: true);
    _acceptedSessionStartedAtHighWater = null;
    _activeEpk = epk;
    _activeRoomId = room;
    _activeRef = nextRef;
    _indexLoaded = false;
    _idToSeq.clear();
    _nextSeq = 0;

    if (nextRef != null) {
      await _loadIndex(nextRef);
      await _materializeTranscriptProjectionForRef(nextRef);
    }
    _writeRuntime();
  }

  /// Clears the in-memory streaming buffer + whole-turn working flag
  /// (emitting the cleared state so listeners update) WITHOUT touching the
  /// durable session index. Used on a session switch — see [activate].
  void _resetTurnState({bool clearPendingSendTimers = false}) {
    _flushTimer?.cancel();
    _flushTimer = null;
    _chunkBuffer.clear();
    _setQueuedText(null);
    if (clearPendingSendTimers) {
      // Session switch: the previous chat's in-flight sends are no longer ours
      // to confirm — drop their backstops so a stale timer can't fire later.
      _cancelAllSendTimers();
    }
    if (_streaming != null) _emitStreaming(null);
    _setTurnViewLocalOnly(TranscriptTurnView.idle);
  }

  Future<void> sendMessage(
    String text, {
    MessageImage? image,
    UserMessageStreamingBehavior? streamingBehavior,
  }) async {
    final ref = _activeRef;
    final epk = _activeEpk;
    final id = _newId();
    final now = DateTime.now();
    final isSteer = streamingBehavior == UserMessageStreamingBehavior.steer;
    final sessionId = ref?.sessionId;
    if (ref == null || sessionId == null || sessionId.isEmpty) {
      debugPrint('[msg-send] id=$id blocked: session identity unavailable');
      return;
    }
    // Optimistic pending row (#defaults: optimistic + dedupe by id).
    if (epk != null) {
      await _appendTranscriptEvent(
        UserMessageSubmitted(
          eventId: 'local:user_submitted:$id',
          sessionId: _activeTranscriptSessionId(),
          ts: now,
          clientMessageId: id,
          text: text,
          image: image,
        ),
        preserveTurnState: isSteer,
      );
      if (!isSteer) {
        _setTurnActive(
          status: AppTurnStatus.working,
          preview: _preview(text, image),
          replyTo: id,
        );
      }
      // Arm the no-echo backstop for this row. The timeout is keyed off the
      // row's `ts`, NOT online-ness: an offline "held pending" send fails
      // visibly after its ts too, and ANY pending row is re-armed on session
      // load (see _loadIndex). So a quick session-switch or an app restart
      // still fails a stale bubble instead of letting it spin "sending…"
      // forever.
      _armSendTimeout(id, now);
    }
    final ch = _conn.channel;
    if (ch == null) {
      debugPrint(
        '[msg-send] id=$id (offline → held pending, fails in '
        '${pendingSendTimeout.inSeconds}s)',
      );
      return;
    }
    // Seed an EMPTY streaming buffer so the blinking cursor shows during the
    // "thinking" gap before the first agent_chunk (pre-31 behavior). In-memory
    // only (#7) — never written to the DB. agent_chunk appends; agent_done
    // clears it (even for a text-less, tool-only turn).
    // Steering messages should not create a new cursor, because they do not
    // start a fresh assistant turn.
    if (!isSteer) {
      _emitStreaming(StreamingMessage(inReplyTo: id));
    }
    debugPrint('[msg-send] id=$id text=${_preview(text, image)}');
    try {
      await ch.send(
        UserMessage(
          id: id,
          sessionId: sessionId,
          text: text,
          streamingBehavior: streamingBehavior,
          images: image == null
              ? null
              : [WireImage(data: image.data, mime: image.mime)],
        ),
      );
    } catch (err) {
      await _failPendingSend(
        id,
        code: 'send_error',
        message:
            'Message could not be sent to the Pi. Check the connection and try again.',
        debugDetail: err,
        expectedRef: ref,
      );
    }
  }

  /// Arm (or re-arm) the no-echo backstop for a pending row, keyed by
  /// `id`. The window is the time REMAINING relative to the row's [ts], so a
  /// row loaded from disk already past [pendingSendTimeout] fires immediately
  /// (floored at zero). Idempotent — cancels any existing timer for `id`.
  void _armSendTimeout(String id, DateTime ts) {
    final ref = _activeRef;
    if (ref == null) return;
    _pendingSendTimers.remove(id)?.cancel();
    final remaining = pendingSendTimeout - DateTime.now().difference(ts);
    _pendingSendTimers[id] = Timer(
      remaining > Duration.zero ? remaining : Duration.zero,
      () => _onSendTimeout(id, ref),
    );
  }

  /// No echo arrived within [pendingSendTimeout]: replace the optimistic
  /// bubble with a visible failure and unwind only the turn state that belongs
  /// to THIS `id`.
  void _onSendTimeout(String id, RemoteSessionRef expectedRef) {
    // ignore: discarded_futures
    _failPendingSend(
      id,
      code: 'send_timeout',
      message:
          'Message was not confirmed by the Pi. It may not have been delivered.',
      debugDetail: 'no echo in ${pendingSendTimeout.inSeconds}s',
      expectedRef: expectedRef,
    );
  }

  Future<void> _failPendingSend(
    String id, {
    required String code,
    required String message,
    Object? debugDetail,
    RemoteSessionRef? expectedRef,
  }) async {
    if (expectedRef != null && !_isStillActive(expectedRef)) return;
    _pendingSendTimers.remove(id)?.cancel();
    if (expectedRef != null && !_isStillActive(expectedRef)) return;
    await _appendTranscriptEvent(
      UserMessageFailed(
        eventId: 'local:user_failed:$id:$code',
        sessionId: expectedRef?.sessionId ?? _activeTranscriptSessionId(),
        ts: DateTime.now(),
        clientMessageId: id,
        code: code,
        message: message,
      ),
    );
    if (expectedRef != null && !_isStillActive(expectedRef)) return;
    // Clear the thinking cursor only if it's seeded for this message.
    if (_streaming?.inReplyTo == id) _emitStreaming(null);
    // Clear working ONLY if this id owns it — never knock down a turn that a
    // different (echoed) message is already driving.
    if (turnProjection.cancelTargetId == id) _setTurnIdle();
    debugPrint(
      '[msg-failed] id=$id code=$code detail=${debugDetail ?? message}',
    );
  }

  void _cancelAllSendTimers() {
    for (final t in _pendingSendTimers.values) {
      t.cancel();
    }
    _pendingSendTimers.clear();
  }

  /// Test seam — number of armed no-echo timers (asserts no leak on reset).
  @visibleForTesting
  int get debugPendingSendTimerCount => _pendingSendTimers.length;

  @visibleForTesting
  TranscriptEventStore get debugTranscriptEventStore => _eventStore;

  @visibleForTesting
  Future<void> debugApplyHistory(SessionHistory history) =>
      _applyHistory(history);

  Future<void> setQueuedMessage(String text) async {
    final ch = _conn.channel;
    if (ch == null) return;
    _setQueuedText(text);
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(
      QueuedMessageSet(id: _newId(), sessionId: ref.sessionId, text: text),
    );
  }

  Future<void> clearQueuedMessage() async {
    final ch = _conn.channel;
    _setQueuedText(null);
    if (ch == null) return;
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(QueuedMessageClear(id: _newId(), sessionId: ref.sessionId));
  }

  Future<void> cancel(String targetId) async {
    // User-driven cancel of this message → disarm its no-echo backstop too.
    _pendingSendTimers.remove(targetId)?.cancel();
    final ch = _conn.channel;
    if (ch == null) return;
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(
      Cancel(id: _newId(), sessionId: ref.sessionId, targetId: targetId),
    );
  }

  Future<void> approveTool(String toolCallId, ApproveDecision decision) async {
    final ch = _conn.channel;
    if (ch == null) return;
    final ref = _activeRef;
    if (ref == null) return;
    await ch.send(
      ApproveTool(
        id: _newId(),
        sessionId: ref.sessionId,
        toolCallId: toolCallId,
        decision: decision,
      ),
    );
    // Tool approval status is ultimately materialized from the transcript/tool
    // event stream. Do not mutate the disposable msgs projection directly here.
  }

  void requestSync() {
    final ch = _conn.channel;
    final ref = _activeRef;
    if (ch == null || ref == null) {
      _pendingSyncRequest = true;
      return;
    }
    _pendingSyncRequest = false;
    ch.send(SessionSync(id: _newId(), sessionId: ref.sessionId)).catchError((
      Object err,
      StackTrace _,
    ) {
      debugPrint('[session-sync] request failed: $err');
    });
  }

  /// Plan/28 — `session_new` acked: wipe the active session's rows.
  /// Keep the persisted `session_started_at` high-water so stale post-clear
  /// history can still be identified from persisted state.
  Future<void> clearActiveSession() async {
    final ref = _activeRef;
    if (ref == null) return;
    // Session wiped → any optimistic sends are moot; disarm their backstops.
    _cancelAllSendTimers();
    await _enqueue(() async {
      if (!_isStillActive(ref)) return;
      final box = await _boxes.msgsBox(ref);
      await box.clear();
      _idToSeq.clear();
      _nextSeq = 0;
      _indexLoaded = true;
      await _clearTranscriptEventsForRef(ref);
      await _rewriteMessageProjectionInWriteChain(
        ref,
        const TranscriptProjection(
          messages: <ChatMessage>[],
          turn: TranscriptTurnView.idle,
        ),
        const <TranscriptEvent>[],
      );
      // Session-clear is a `session_new` wipe boundary: a clear during an
      // active turn would otherwise leave the turn projection / streaming
      // cursor stuck on a stale cancel target. Reset the whole-turn state so
      // working converges false.
      // (`_cancelAllSendTimers()` already ran above; no need to repeat.)
      _resetTurnState();
    });
  }

  // ---------------------------------------------------------------------------
  // Channel → DB
  // ---------------------------------------------------------------------------

  void _onStatus(ConnectionStatus s) {
    _msgSub?.cancel();
    _msgSub = null;
    if (s is StatusOnline) {
      // Plan/32f — bind this stream's writes to the PEER that owns the
      // channel RIGHT NOW. After a `switchTo`, a late frame from the OLD
      // peer's channel must not land in the NEW session's box: `_activeEpk`
      // has already moved (the chat calls `activate()` before `switchTo`), so
      // a straggler chat-1 frame would otherwise be written to chat-2's box
      // and bleed across until chat-2's history re-applied. We capture the
      // origin epk here and drop frames whose origin is no longer active.
      //
      // We gate on epk only — NOT room: rooms of the same peer share one
      // channel and `_onStatus` doesn't re-fire on a same-peer room switch
      // (the transport already demuxes by room), so a room gate would wrongly
      // drop everything after switching cwds on the same Mac.
      final originEpk = _conn.activePeer?.remoteEpk;
      _msgSub = s.channel.serverMessages.listen(
        (msg) => _onServerMessage(msg, originEpk),
        onError: (Object _, StackTrace _) {},
      );
      // ignore: discarded_futures
      _onlineActivated();
    } else {
      // Any non-online edge is a reliability boundary: clear the active
      // room-local stream/working state immediately so the old room doesn't
      // keep a stale cancel target/cursor while the relay reconnects. Keep
      // pending-send backstops armed so a disconnect can still become a visible
      // failure if no echo ever arrives.
      _resetTurnState(clearPendingSendTimers: false);
      _setTurnIdle();
    }
    _writeRuntime();
  }

  Future<void> _onlineActivated() async {
    final peer = _conn.activePeer;
    if (peer != null && _activeEpk == null) {
      await activate(peer.remoteEpk, _conn.activeRoomId);
    }
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(milliseconds: 200), requestSync);
    if (_pendingSyncRequest) requestSync();
  }

  void _onRoomsChanged() {
    _writeRuntime();
    final epk = _activeEpk;
    if (epk == null) return;
    final nextRef = _resolveActiveRef(epk, _activeRoomId);
    if (nextRef != _activeRef) {
      // A Pi `/new`, `/resume`, or daemon replacement can rotate the canonical
      // session id while the relay room stays the same. Rebind persistence to
      // the new session-scoped box and clear in-memory turn state.
      // ignore: discarded_futures
      activate(epk, _activeRoomId);
    }
  }

  void _onServerMessage(ServerMessage msg, [String? originEpk]) {
    // Plan/32f — drop frames from a peer whose channel is no longer the active
    // session (a stale connection still draining after `switchTo`). Without
    // this, a straggler write targets `_activeEpk` — which already points at
    // the NEW chat — and bleeds the old session's messages into the new box.
    // Only gate when BOTH origin and active are set and differ: pre-bind
    // (`_activeEpk == null`, cold boot before `activate`) must still flow, and
    // direct test calls without an origin aren't gated.
    if (originEpk != null && _activeEpk != null && originEpk != _activeEpk) {
      return;
    }
    final gate = _sessionGate.accepts(msg, _activeRef);
    if (!gate.accepted) {
      debugPrint(
        '[session-gate] drop type=${gate.messageType ?? typeOfServerMessage(msg)} '
        'room=$_activeRoomId reason=${gate.reason} '
        'msg_session=${_shortSessionId(gate.messageSessionId)} '
        'active_session=${_shortSessionId(gate.expectedSessionId)}',
      );
      return;
    }
    switch (msg) {
      case AgentChunk(:final inReplyTo, :final delta):
        // ignore: discarded_futures
        _appendTranscriptEvent(
          AssistantDeltaReceived(
            eventId: 'server:assistant_delta:$inReplyTo:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            replyTo: inReplyTo,
            delta: delta,
          ),
        );
        _setTurnActive(status: AppTurnStatus.streaming, replyTo: inReplyTo);

      case AgentDone(:final inReplyTo):
        final buffered = _streaming?.buffer ?? '';
        if (buffered.isNotEmpty) {
          // ignore: discarded_futures
          _appendTranscriptEvent(
            AssistantMessageCommitted(
              eventId: 'server:assistant_committed:$inReplyTo:${uuid7()}',
              sessionId: _activeTranscriptSessionId(),
              ts: DateTime.now(),
              messageId: 'agent_${uuid7()}',
              replyTo: inReplyTo,
              text: buffered,
            ),
          );
        }
        // ignore: discarded_futures
        _appendTranscriptEvent(
          AssistantDoneReceived(
            eventId: 'server:assistant_done:$inReplyTo:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            replyTo: inReplyTo,
          ),
        );
        _setTurnIdle(preview: buffered.isEmpty ? null : buffered);

      case AgentMessage(:final inReplyTo, :final text):
        // ignore: discarded_futures
        _appendTranscriptEvent(
          AssistantMessageCommitted(
            eventId: 'server:assistant_message:$inReplyTo:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            messageId: 'agent_$inReplyTo',
            replyTo: inReplyTo,
            text: text,
          ),
        );

      case QueuedMessageState(:final text):
        _setQueuedText(text?.isNotEmpty == true ? text : null);

      case UserInput(
        :final id,
        :final text,
        :final image,
        :final streamingBehavior,
      ):
        // Echo dedupes against the optimistic row (same id): confirm it
        // (pending=false) or insert as confirmed (foreign device).
        debugPrint('[msg-echo] id=$id');
        // Echo arrived → the send landed; disarm the no-echo backstop.
        _pendingSendTimers.remove(id)?.cancel();
        // ignore: discarded_futures
        _appendTranscriptEvent(
          UserMessageConfirmed(
            eventId: 'server:user_confirmed:$id',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            clientMessageId: id,
            text: text,
            image: image == null
                ? null
                : MessageImage(data: image.data, mime: image.mime),
            streamingBehavior: streamingBehavior,
          ),
          preserveTurnState: true,
        );
        // Steering input should not start/replace the working turn bubble.
        if (streamingBehavior == UserMessageStreamingBehavior.steer) {
          _setActivity(SessionActivity.working, preview: text);
        } else {
          _setTurnActive(
            status: AppTurnStatus.working,
            preview: text,
            replyTo: id,
          );
          // Show the thinking cursor for this turn (foreign-device echo, or the
          // local echo when the send-seed was already cleared). Guarded so it
          // never wipes a buffer that's already accumulating for this id.
          if (_streaming?.inReplyTo != id) {
            _emitStreaming(StreamingMessage(inReplyTo: id));
          }
        }

      case ToolRequest(:final toolCallId, :final tool, :final args):
        // Sequential ordering: close the current text segment as its own row
        // BEFORE the tool, so "narration → command → narration" renders in
        // order instead of all text landing after the commands.
        final buffered = _streaming?.buffer ?? '';
        if (buffered.isNotEmpty) {
          // ignore: discarded_futures
          _appendTranscriptEvent(
            AssistantMessageCommitted(
              eventId: 'server:assistant_committed:$toolCallId:${uuid7()}',
              sessionId: _activeTranscriptSessionId(),
              ts: DateTime.now(),
              messageId: 'agent_${uuid7()}',
              replyTo: _streaming!.inReplyTo,
              text: buffered,
            ),
          );
        }
        // ignore: discarded_futures
        _appendTranscriptEvent(
          ToolRequested(
            eventId: 'server:tool_requested:$toolCallId',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            toolCallId: toolCallId,
            tool: tool,
            args: _objectMap(args),
          ),
        );

      case ToolResult(:final toolCallId, :final result, :final error):
        // ignore: discarded_futures
        _appendTranscriptEvent(
          ToolFinished(
            eventId: 'server:tool_finished:$toolCallId',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            toolCallId: toolCallId,
            result: result,
            error: error,
          ),
        );

      case Cancelled(:final targetId):
        _pendingSendTimers.remove(targetId)?.cancel();
        _discardStreamingState();
        // Cancel is stop-generation, not delete-history. If the target was
        // still only a local optimistic send, materialize it as failed through
        // the event log; confirmed history stays visible and the terminal done
        // event converges the turn idle through the projection.
        // ignore: discarded_futures
        _appendTranscriptEvents(<TranscriptEvent>[
          UserMessageFailed(
            eventId: 'server:user_cancelled:$targetId',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            clientMessageId: targetId,
            code: 'cancelled',
            message: 'Message was cancelled before delivery was confirmed.',
          ),
          AssistantDoneReceived(
            eventId: 'server:assistant_cancelled:$targetId:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            replyTo: targetId,
          ),
        ]);
        _setTurnIdle();

      case Bye(:final rawReason):
        if (!_eventController.isClosed) {
          _eventController.add(PeerWentOffline(rawReason));
        }
        _setTurnIdle();
        final peer = _conn.activePeer;
        if (peer != null) {
          // ignore: discarded_futures
          _conn.switchTo(peer);
        }

      case SessionHistory():
        // ignore: discarded_futures
        _applyHistory(msg);

      case ErrorMessage(:final inReplyTo, :final code, :final message):
        if (code.contains('unknown_peer')) {
          if (!_eventController.isClosed) {
            _eventController.add(const PairingRevoked());
          }
          break;
        }
        _discardStreamingState();
        _setTurnIdle();
        // ignore: discarded_futures
        _appendTranscriptEvents(<TranscriptEvent>[
          AssistantMessageCommitted(
            eventId: 'server:error_message:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            messageId: 'err_${uuid7()}',
            replyTo: inReplyTo ?? 'error',
            text: '⚠ $code: $message',
          ),
          AssistantDoneReceived(
            eventId: 'server:error_done:${uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: DateTime.now(),
            replyTo: inReplyTo ?? 'error',
          ),
        ]);

      case Compaction(:final summary, :final tokensBefore, :final ts):
        // ignore: discarded_futures
        _appendTranscriptEvent(
          CompactionRecorded(
            eventId: 'server:compaction:${ts ?? uuid7()}',
            sessionId: _activeTranscriptSessionId(),
            ts: ts != null
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : DateTime.now(),
            summary: summary,
            tokensBefore: tokensBefore,
          ),
        );

      case Pong():
      case PairOk():
      case PairError():
      case ActionOk():
      case ActionError():
      case ModelsList():
        break;
    }
  }

  static String _shortSessionId(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) return '-';
    return sessionId.length <= 8
        ? sessionId
        : '…${sessionId.substring(sessionId.length - 8)}';
  }

  /// Plan/32 — persist a compaction as a system row so it renders a system
  /// bubble in the chat and survives a re-sync. Keyed by `ts` when present so
  /// the live message and its history replay collapse to one row.
  String _activeTranscriptSessionId() =>
      _activeRef?.sessionId ?? 'inactive-session';

  Future<void> _appendTranscriptEvent(
    TranscriptEvent event, {
    bool preserveTurnState = false,
  }) => _appendTranscriptEvents(<TranscriptEvent>[
    event,
  ], preserveTurnState: preserveTurnState);

  Future<void> _appendTranscriptEvents(
    Iterable<TranscriptEvent> events, {
    bool preserveTurnState = false,
  }) async {
    final key = _activeTranscriptKeyOrNull();
    if (key == null) return;
    final batch = events
        .where((event) => event.sessionId == key.sessionId)
        .toList(growable: false);
    if (batch.isEmpty) return;

    await _enqueue(() async {
      final ref = _activeRef;
      if (ref == null || !_sameTranscriptKey(key, ref)) return;
      final result = await _eventStore.appendAll(key, batch);
      if (result.appended == 0) return;
      final log = await _eventStore.readSession(key);
      final projection = deriveTranscriptProjection(
        sessionId: key.sessionId,
        events: log,
      );
      if (!preserveTurnState) {
        _emitStreaming(projection.streaming);
        _setTurnView(projection.turn);
      }
      await _rewriteMessageProjectionInWriteChain(ref, projection, log);
    });
  }

  Future<void> _materializeTranscriptProjectionForRef(RemoteSessionRef ref) {
    final key = _transcriptKeyForRef(ref);
    return _enqueue(() async {
      if (!_isStillActive(ref)) return;
      final log = await _eventStore.readSession(key);
      final projection = deriveTranscriptProjection(
        sessionId: key.sessionId,
        events: log,
      );
      _emitStreaming(projection.streaming);
      _setTurnView(projection.turn);
      await _rewriteMessageProjectionInWriteChain(ref, projection, log);
    });
  }

  Future<void> _clearTranscriptEventsForRef(RemoteSessionRef ref) async {
    final key = _transcriptKeyForRef(ref);
    final box = await _boxes.transcriptEventsBox(key);
    await box.clear();
  }

  /// Canonical transcript key for the active session, or null while relay
  /// room state is known but the SDK `session_id` is not. The null path is a
  /// compatibility-only quarantine: transcript events/projections must wait
  /// rather than falling back to old peer+room boxes.
  TranscriptSessionKey? _activeTranscriptKeyOrNull() {
    final ref = _activeRef;
    return ref == null ? null : _transcriptKeyForRef(ref);
  }

  TranscriptSessionKey _transcriptKeyForRef(RemoteSessionRef ref) =>
      TranscriptSessionKey(
        peerId: ref.peerEpk,
        roomId: ref.roomId,
        sessionId: ref.sessionId,
      );

  bool _sameTranscriptKey(TranscriptSessionKey key, RemoteSessionRef ref) =>
      key.peerId == ref.peerEpk &&
      key.roomId == ref.roomId &&
      key.sessionId == ref.sessionId;

  Future<void> _rewriteMessageProjectionInWriteChain(
    RemoteSessionRef ref,
    TranscriptProjection projection,
    List<TranscriptEvent> log,
  ) async {
    if (!_isStillActive(ref)) return;
    final desired = <MessageRecord>[
      for (var i = 0; i < projection.messages.length; i++)
        _recordFromProjectedMessage(projection.messages[i], i, log),
    ];
    final box = await _boxes.msgsBox(ref);
    for (final k in box.keys.toList()) {
      if ((k as num).toInt() >= desired.length) {
        await box.delete(k);
      }
    }
    for (var i = 0; i < desired.length; i++) {
      final newJson = desired[i].toJson();
      final curRaw = box.get(i);
      final curJson = curRaw == null
          ? null
          : MessageRecord.fromJson(_coerce(curRaw)).toJson();
      if (curJson == null || !_sameMessageRecordJson(curJson, newJson)) {
        await box.put(i, newJson);
      }
    }
    _idToSeq
      ..clear()
      ..addEntries([
        for (var i = 0; i < desired.length; i++)
          MapEntry(_key(desired[i].role, desired[i].id), i),
      ]);
    _nextSeq = desired.length;
    _indexLoaded = true;
    _reconcilePendingSendTimers(desired);
  }

  MessageRecord _recordFromProjectedMessage(
    ChatMessage message,
    int seq,
    List<TranscriptEvent> log,
  ) {
    final ts = _timestampForProjectedMessage(message, log) ?? DateTime.now();
    return switch (message) {
      UserMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.user,
        text: message.text,
        image: message.image,
        status: message.status,
        ts: ts,
      ),
      AssistantMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.assistant,
        text: message.text,
        ts: ts,
      ),
      ToolEvent() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.tool,
        ts: ts,
        tool: ToolEventData(
          toolCallId: message.toolCallId,
          tool: message.tool,
          args: message.args,
          status: message.status,
          result: message.result,
          error: message.error,
        ),
      ),
      CompactionMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.compaction,
        text: message.summary,
        tokensBefore: message.tokensBefore,
        ts: ts,
      ),
    };
  }

  DateTime? _timestampForProjectedMessage(
    ChatMessage message,
    List<TranscriptEvent> log,
  ) {
    DateTime? ts;
    for (final event in log) {
      switch ((message, event)) {
        case (UserMsg(:final id), UserMessageConfirmed(:final clientMessageId))
            when id == clientMessageId:
          ts = event.ts;
        case (UserMsg(:final id), UserMessageSubmitted(:final clientMessageId))
            when id == clientMessageId && ts == null:
          ts = event.ts;
        case (UserMsg(:final id), UserMessageFailed(:final clientMessageId))
            when id == clientMessageId:
          ts = event.ts;
        case (
              AssistantMsg(:final id),
              AssistantMessageCommitted(:final messageId),
            )
            when id == messageId:
          ts = event.ts;
        case (
              ToolEvent(toolCallId: final messageToolCallId),
              ToolRequested(toolCallId: final eventToolCallId),
            )
            when messageToolCallId == eventToolCallId && ts == null:
          ts = event.ts;
        case (
              ToolEvent(toolCallId: final messageToolCallId),
              ToolFinished(toolCallId: final eventToolCallId),
            )
            when messageToolCallId == eventToolCallId:
          ts = event.ts;
        case (CompactionMsg(:final id), CompactionRecorded())
            when id == event.eventId:
          ts = event.ts;
        default:
          break;
      }
    }
    return ts;
  }

  void _reconcilePendingSendTimers(List<MessageRecord> desired) {
    final pendingIds = <String>{
      for (final record in desired)
        if (record.role == MsgRole.user && record.pending) record.id,
    };
    for (final id in _pendingSendTimers.keys.toList()) {
      if (!pendingIds.contains(id)) _pendingSendTimers.remove(id)?.cancel();
    }
    for (final record in desired) {
      if (record.role == MsgRole.user && record.pending) {
        _armSendTimeout(record.id, record.ts);
      }
    }
  }

  Future<void> _applyHistory(SessionHistory h) async {
    final ref = _activeRef;
    if (ref == null) return;
    if (h.sessionId != ref.sessionId) return;
    final incomingStartedAt = h.sessionStartedAt;

    if (_acceptedSessionStartedAtHighWater != null &&
        incomingStartedAt < _acceptedSessionStartedAtHighWater!) {
      return;
    }

    await _appendTranscriptEvents(
      sessionHistoryToTranscriptEvents(history: h, sessionId: ref.sessionId),
    );

    final shouldAdvanceSessionHighWater =
        _acceptedSessionStartedAtHighWater == null ||
        incomingStartedAt > _acceptedSessionStartedAtHighWater!;
    if (shouldAdvanceSessionHighWater) {
      _acceptedSessionStartedAtHighWater = incomingStartedAt;
      _updateIndex(
        (cur) => cur.copyWith(
          sessionStartedAt: DateTime.fromMillisecondsSinceEpoch(
            incomingStartedAt,
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Box write helpers (all serialised through _enqueue)
  // ---------------------------------------------------------------------------

  String _key(MsgRole role, String id) => '${role.name}:$id';

  Future<void> _loadIndex(RemoteSessionRef ref) {
    return _enqueue(() async {
      if (!_isStillActive(ref)) return;
      final box = await _boxes.msgsBox(ref);
      final idx = _boxes.sessionsIndexBox();
      final indexRaw = idx.get(LocalBoxes.sessionKey(ref));
      final indexRecord = indexRaw is Map<String, dynamic>
          ? SessionIndexRecord.tryFromJson(indexRaw)
          : indexRaw is Map
          ? SessionIndexRecord.tryFromJson(indexRaw.cast<String, dynamic>())
          : null;
      _acceptedSessionStartedAtHighWater =
          indexRecord?.sessionStartedAt?.millisecondsSinceEpoch;
      _idToSeq.clear();
      _nextSeq = 0;
      for (final k in box.keys) {
        final seq = (k as num).toInt();
        final r = MessageRecord.fromJson(_coerce(box.get(k)));
        _idToSeq[_key(r.role, r.id)] = seq;
        _nextSeq = math.max(_nextSeq, seq + 1);
        // Re-arm the no-echo backstop for any pending row this session owns, so
        // a bubble persisted across an app restart / quick session-switch fails
        // by its `ts` instead of spinning forever (already-stale → fires
        // immediately). Timers were cleared by _resetTurnState before this load.
        if (r.role == MsgRole.user && r.pending) _armSendTimeout(r.id, r.ts);
      }
      _indexLoaded = true;
    });
  }

  void _setActivity(SessionActivity status, {String? preview}) {
    _updateIndex(
      (cur) => cur.copyWith(
        status: status,
        lastMessageAt: preview != null ? DateTime.now() : null,
        lastMessagePreview: preview,
      ),
    );
  }

  void _setQueuedText(String? text) {
    if (_queuedText == text) return;
    _queuedText = text;
    if (!_queuedController.isClosed) _queuedController.add(text);
  }

  void _setTurnViewLocalOnly(TranscriptTurnView next) {
    if (_sameTurnView(_turnView, next)) return;
    _turnView = next;
    if (!_turnViewController.isClosed) _turnViewController.add(next);
  }

  /// Single source of the active session's turn projection. Drives the
  /// in-memory turn stream (chat pill/cancel target), durable session index,
  /// and the active-room relay compatibility correction.
  void _setTurnView(TranscriptTurnView next, {String? preview}) {
    final sameTurn = _sameTurnView(_turnView, next);
    final epk = _activeEpk;
    if (sameTurn && preview == null) {
      if (epk != null) {
        _conn.markRoomWorking(epk, _activeRoomId, next.working);
      }
      return;
    }
    _setActivity(
      next.working ? SessionActivity.working : SessionActivity.idle,
      preview: preview,
    );
    if (epk != null) {
      _conn.markRoomWorking(epk, _activeRoomId, next.working);
    }
    if (sameTurn) return;
    _turnView = next;
    if (!_turnViewController.isClosed) _turnViewController.add(next);
  }

  void _setTurnActive({
    required AppTurnStatus status,
    String? preview,
    String? turnId,
    String? replyTo,
  }) {
    final target = replyTo ?? _turnView.replyTo ?? turnId;
    _setTurnView(
      TranscriptTurnView(
        status: status,
        turnId: turnId ?? _turnView.turnId ?? target,
        replyTo: target,
      ),
      preview: preview,
    );
  }

  void _setTurnIdle({String? preview}) =>
      _setTurnView(TranscriptTurnView.idle, preview: preview);

  bool _sameTurnView(TranscriptTurnView left, TranscriptTurnView right) =>
      left.status == right.status &&
      left.turnId == right.turnId &&
      left.replyTo == right.replyTo &&
      left.error == right.error;

  void _updateIndex(SessionIndexRecord Function(SessionIndexRecord cur) build) {
    final ref = _activeRef;
    if (ref == null) return;
    // ignore: discarded_futures
    _enqueue(() async {
      if (!_isStillActive(ref)) return;
      final idx = _boxes.sessionsIndexBox();
      final key = LocalBoxes.sessionKey(ref);
      final raw = idx.get(key);
      final cur = raw is Map
          ? SessionIndexRecord.tryFromJson(raw.cast<String, dynamic>())
          : null;
      final base =
          cur ??
          SessionIndexRecord(
            epk: ref.peerEpk,
            roomId: ref.roomId,
            sessionId: ref.sessionId,
          );
      await idx.put(key, build(base).toJson());
    });
  }

  void _writeRuntime() {
    final epk = _activeEpk;
    if (epk == null) return;
    final room = _activeRoomId;
    final s = _conn.status;
    final conn = switch (s) {
      StatusOnline() => RuntimeConnection.online,
      StatusConnecting() => RuntimeConnection.connecting,
      StatusRetrying() => RuntimeConnection.retrying,
      StatusOffline() => RuntimeConnection.offline,
      StatusNoPeer() => RuntimeConnection.connecting,
    };
    final presence = (s is StatusOnline && _conn.isRoomLive(epk, room))
        ? RuntimePresence.alive
        : (s is StatusOnline ? RuntimePresence.stale : RuntimePresence.unknown);
    // ignore: discarded_futures
    _enqueue(() async {
      _boxes.runtimeBox().put(
        LocalBoxes.runtimeKey(epk, room),
        RuntimeRecord(connection: conn, presence: presence).toJson(),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Streaming (in-memory only)
  // ---------------------------------------------------------------------------

  void _discardStreamingState() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _chunkBuffer.clear();
    _emitStreaming(null);
  }

  void _emitStreaming(StreamingMessage? s) {
    _streaming = s;
    if (!_streamingController.isClosed) _streamingController.add(s);
  }

  // ---------------------------------------------------------------------------

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _writeChain.then((_) => op());
    _writeChain = next.catchError((Object _, StackTrace _) {});
    return next;
  }

  static Map<String, dynamic> _coerce(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  static bool _sameMessageRecordJson(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final normalizedLeft = Map<String, dynamic>.of(left)..remove('ts');
    final normalizedRight = Map<String, dynamic>.of(right)..remove('ts');
    return jsonEncode(normalizedLeft) == jsonEncode(normalizedRight);
  }

  static Map<String, Object?> _objectMap(Object? raw) {
    if (raw == null) return <String, Object?>{};
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return raw.map((key, value) {
        if (key is! String) {
          throw const FormatException('Tool request args keys must be strings');
        }
        return MapEntry(key, value as Object?);
      });
    }
    throw const FormatException('Tool request args must be an object');
  }

  static String _preview(String text, MessageImage? image) {
    if (text.isEmpty && image != null) return '📷 Image';
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }

  static String _newId() => 'cli_${uuid7()}';

  @override
  void dispose() {
    _resetTurnState(clearPendingSendTimers: true);
    _flushTimer?.cancel();
    _syncDebounce?.cancel();
    _cancelAllSendTimers();
    _connSub?.cancel();
    _msgSub?.cancel();
    _roomsSub?.cancel();
    _presenceSub?.cancel();
    _streamingController.close();
    _eventController.close();
    _turnViewController.close();
    _queuedController.close();
  }
}
