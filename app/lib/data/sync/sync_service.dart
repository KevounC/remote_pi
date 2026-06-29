// Plan/31 — SyncService: the SINGLE writer of the local SSOT.
//
// Consumes the channel (ConnectionManager status + PeerChannel
// serverMessages) and writes row-granular records to Hive (v2 boxes). The UI
// never touches this stream — it reads the DB via the read repositories.
//
// Streaming is the ONE exception to SSOT (#7): AgentChunk deltas are coalesced
// into an in-memory Stream<StreamingMessage?> and NEVER written to the DB; only
// the finalized message lands in the box on `agent_done`.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app/data/local/boxes.dart';
import 'package:app/data/local/records/message_record.dart';
import 'package:app/data/local/records/runtime_record.dart';
import 'package:app/data/local/records/session_index_record.dart';
import 'package:app/data/sync/sync_events.dart';
import 'package:app/data/sync/session_gate.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/service.dart';
import 'package:app/domain/contracts/transcript_event_store.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/protocol/uuid7.dart';
import 'package:flutter/foundation.dart';

class SyncService extends Service {
  final ConnectionManager _conn;
  final LocalBoxes _boxes;
  final TranscriptEventStore? _transcriptEventStore;
  final SessionGate _sessionGate = const SessionGate();

  StreamSubscription<ConnectionStatus>? _connSub;
  StreamSubscription<ServerMessage>? _msgSub;
  StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
  StreamSubscription<Map<String, PresenceState>>? _presenceSub;

  // Active session being written (follows ConnectionManager).
  String? _activeEpk;
  String _activeRoomId = 'main';

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

  final List<TranscriptEvent> _transcriptEvents = <TranscriptEvent>[];
  final Set<String> _transcriptEventIds = <String>{};

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

  // Whether the active session's agent is currently producing a reply. Spans
  // the WHOLE turn (send/echo → agent_done), not just the token-streaming
  // window — restoring the old broad "working" signal. Mirrored into the
  // session index (durable, for Home) and exposed in-memory (for the chat
  // pill, no box-key matching needed).
  bool _working = false;
  // Id of the user message the in-flight reply is answering — the `cancel`
  // target while working. Null when idle.
  String? _workingReplyTo;
  final StreamController<bool> _workingController =
      StreamController<bool>.broadcast();

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
  }) : _transcriptEventStore = transcriptEventStore {
    _connSub = _conn.statusStream.listen(_onStatus);
    _roomsSub = _conn.roomsStream.listen((_) => _writeRuntime());
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

  /// True while the active session's agent is producing a reply (whole turn).
  bool get isWorking => _working;
  Stream<bool> get workingStream => _workingController.stream;

  /// `cancel` target for the in-flight reply (null when idle).
  String? get workingReplyTo => _workingReplyTo;

  String? get activeEpk => _activeEpk;
  String get activeRoomId => _activeRoomId;

  /// Bind the writer to a (peer, room). Opens the box and rebuilds the
  /// dedupe/seq index from it. Called by the chat when it mounts / switches
  /// rooms; also adopted automatically on the first StatusOnline.
  Future<void> activate(String epk, String roomId) async {
    final room = roomId.isEmpty ? 'main' : roomId;
    if (_activeEpk == epk && _activeRoomId == room && _indexLoaded) return;
    // Genuine session switch: drop the in-memory turn state so the
    // PREVIOUS session's streaming buffer + whole-turn working flag can't
    // bleed into the next chat (the bug where chat 2 looked "working"
    // because chat 1 was mid-turn). We deliberately do NOT clear the
    // durable session index — the previous room may still be running on
    // the Pi, and Home keeps showing it via the relay's per-room
    // `meta.working` broadcast.
    _resetTurnState(clearPendingSendTimers: true);
    _activeEpk = epk;
    _activeRoomId = room;
    await _loadIndex();
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
    _workingReplyTo = null;
    if (_streaming != null) _emitStreaming(null);
    if (_working) {
      _working = false;
      if (!_workingController.isClosed) _workingController.add(false);
    }
  }

  Future<void> sendMessage(
    String text, {
    MessageImage? image,
    UserMessageStreamingBehavior? streamingBehavior,
  }) async {
    final epk = _activeEpk;
    final room = _activeRoomId;
    final id = _newId();
    final now = DateTime.now();
    final isSteer = streamingBehavior == UserMessageStreamingBehavior.steer;
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
      );
      if (!isSteer) {
        _setWorking(true, preview: _preview(text, image), replyTo: id);
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
    final sessionId = _activeSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      await _failPendingSend(
        id,
        code: 'session_unavailable',
        message:
            'Session identity is not available yet. Reconnect and try again.',
        expectedEpk: epk,
        expectedRoom: room,
      );
      return;
    }
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
        expectedEpk: epk,
        expectedRoom: room,
      );
    }
  }

  /// Arm (or re-arm) the no-echo backstop for a pending row, keyed by
  /// `id`. The window is the time REMAINING relative to the row's [ts], so a
  /// row loaded from disk already past [pendingSendTimeout] fires immediately
  /// (floored at zero). Idempotent — cancels any existing timer for `id`.
  void _armSendTimeout(String id, DateTime ts) {
    final epk = _activeEpk;
    if (epk == null) return;
    final room = _activeRoomId;
    _pendingSendTimers.remove(id)?.cancel();
    final remaining = pendingSendTimeout - DateTime.now().difference(ts);
    _pendingSendTimers[id] = Timer(
      remaining > Duration.zero ? remaining : Duration.zero,
      () => _onSendTimeout(id, epk, room),
    );
  }

  /// No echo arrived within [pendingSendTimeout]: replace the optimistic
  /// bubble with a visible failure and unwind only the turn state that belongs
  /// to THIS `id`.
  void _onSendTimeout(String id, String epk, String room) {
    // ignore: discarded_futures
    _failPendingSend(
      id,
      code: 'send_timeout',
      message:
          'Message was not confirmed by the Pi. It may not have been delivered.',
      debugDetail: 'no echo in ${pendingSendTimeout.inSeconds}s',
      expectedEpk: epk,
      expectedRoom: room,
    );
  }

  Future<void> _failPendingSend(
    String id, {
    required String code,
    required String message,
    Object? debugDetail,
    String? expectedEpk,
    String? expectedRoom,
  }) async {
    if (expectedEpk != null &&
        (_activeEpk != expectedEpk || _activeRoomId != expectedRoom)) {
      return;
    }
    _pendingSendTimers.remove(id)?.cancel();
    await _removePendingById(id);
    if (expectedEpk != null &&
        (_activeEpk != expectedEpk || _activeRoomId != expectedRoom)) {
      return;
    }
    // Clear the thinking cursor only if it's seeded for this message.
    if (_streaming?.inReplyTo == id) _emitStreaming(null);
    // Clear working ONLY if this id owns it — never knock down a turn that a
    // different (echoed) message is already driving.
    if (_workingReplyTo == id) _setWorking(false);
    await _upsert(
      MsgRole.assistant,
      'err_$id',
      (seq, existing) =>
          existing ??
          MessageRecord(
            id: 'err_$id',
            seq: seq,
            role: MsgRole.assistant,
            text: '⚠ $code: $message',
            ts: DateTime.now(),
          ),
    );
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
  TranscriptEventStore? get debugTranscriptEventStore => _transcriptEventStore;

  String? get _activeSessionId => _conn.activeSessionId;

  Future<void> setQueuedMessage(String text) async {
    final ch = _conn.channel;
    if (ch == null) return;
    _setQueuedText(text);
    final sessionId = _activeSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    await ch.send(
      QueuedMessageSet(id: _newId(), sessionId: sessionId, text: text),
    );
  }

  Future<void> clearQueuedMessage() async {
    final ch = _conn.channel;
    _setQueuedText(null);
    if (ch == null) return;
    final sessionId = _activeSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    await ch.send(QueuedMessageClear(id: _newId(), sessionId: sessionId));
  }

  Future<void> cancel(String targetId) async {
    // User-driven cancel of this message → disarm its no-echo backstop too.
    _pendingSendTimers.remove(targetId)?.cancel();
    final ch = _conn.channel;
    if (ch == null) return;
    final sessionId = _activeSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    await ch.send(
      Cancel(id: _newId(), sessionId: sessionId, targetId: targetId),
    );
  }

  Future<void> approveTool(String toolCallId, ApproveDecision decision) async {
    final ch = _conn.channel;
    if (ch == null) return;
    final sessionId = _activeSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    await ch.send(
      ApproveTool(
        id: _newId(),
        sessionId: sessionId,
        toolCallId: toolCallId,
        decision: decision,
      ),
    );
    await _upsert(MsgRole.tool, toolCallId, (seq, existing) {
      final base =
          existing?.tool ??
          ToolEventData(toolCallId: toolCallId, tool: 'unknown');
      return (existing ??
              MessageRecord(
                id: toolCallId,
                seq: seq,
                role: MsgRole.tool,
                ts: DateTime.now(),
              ))
          .copyWith(
            tool: base.copyWith(
              status: decision == ApproveDecision.allow
                  ? ToolEventStatus.allowed
                  : ToolEventStatus.denied,
            ),
          );
    });
  }

  void requestSync() {
    final ch = _conn.channel;
    if (ch == null || _activeEpk == null) {
      _pendingSyncRequest = true;
      return;
    }
    _pendingSyncRequest = false;
    final sessionId = _activeSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      _pendingSyncRequest = true;
      return;
    }
    ch.send(SessionSync(id: _newId(), sessionId: sessionId));
  }

  /// Plan/28 — `session_new` acked: wipe the active session's rows.
  /// Keep the persisted `session_started_at` high-water so stale post-clear
  /// history can still be identified from persisted state.
  Future<void> clearActiveSession() async {
    final epk = _activeEpk;
    if (epk == null) return;
    final room = _activeRoomId;
    // Session wiped → any optimistic sends are moot; disarm their backstops.
    _cancelAllSendTimers();
    await _enqueue(() async {
      if (_activeEpk != epk || _activeRoomId != room) return;
      final box = await _boxes.msgsBox(epk, room);
      await box.clear();
      _idToSeq.clear();
      _nextSeq = 0;
      _indexLoaded = true;
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
      _setWorking(false);
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
    final gate = _sessionGate.accepts(msg, _activeSessionRef());
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
        _setWorking(true, replyTo: inReplyTo);

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
        _setWorking(false, preview: buffered.isEmpty ? null : buffered);

      case AgentMessage(:final inReplyTo, :final text):
        // ignore: discarded_futures
        _upsert(
          MsgRole.assistant,
          inReplyTo,
          (seq, existing) =>
              existing ??
              MessageRecord(
                id: inReplyTo,
                seq: seq,
                role: MsgRole.assistant,
                text: text,
                ts: DateTime.now(),
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
        );
        // Steering input should not start/replace the working turn bubble.
        if (streamingBehavior == UserMessageStreamingBehavior.steer) {
          _setActivity(SessionActivity.working, preview: text);
        } else {
          _setWorking(true, preview: text, replyTo: id);
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
            args: args,
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
        // Cancel is stop-generation, not delete-history. Only drop a local
        // optimistic row that never got confirmed by the Pi echo; preserve
        // confirmed user/tool rows as the audit trail of what happened.
        // ignore: discarded_futures
        _removePendingById(targetId);
        _setWorking(false);

      case Bye(:final rawReason):
        if (!_eventController.isClosed) {
          _eventController.add(PeerWentOffline(rawReason));
        }
        _setWorking(false);
        final peer = _conn.activePeer;
        if (peer != null) {
          // ignore: discarded_futures
          _conn.switchTo(peer);
        }

      case SessionHistory():
        // ignore: discarded_futures
        _applyHistory(msg);

      case ErrorMessage(:final code, :final message):
        if (code.contains('unknown_peer')) {
          if (!_eventController.isClosed) {
            _eventController.add(const PairingRevoked());
          }
          break;
        }
        _discardStreamingState();
        _setWorking(false);
        // ignore: discarded_futures
        _upsert(
          MsgRole.assistant,
          _newId(),
          (seq, _) => MessageRecord(
            id: 'err_$seq',
            seq: seq,
            role: MsgRole.assistant,
            text: '⚠ $code: $message',
            ts: DateTime.now(),
          ),
        );

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

  ActiveSessionRef? _activeSessionRef() {
    final epk = _activeEpk;
    final sessionId = _activeSessionId;
    if (epk == null || sessionId == null || sessionId.isEmpty) return null;
    return ActiveSessionRef(
      peerEpk: epk,
      roomId: _activeRoomId,
      sessionId: sessionId,
    );
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
  String _activeTranscriptSessionId() {
    final sessionId = _activeSessionId;
    if (sessionId != null && sessionId.isNotEmpty) return sessionId;
    final epk = _activeEpk ?? 'unknown-peer';
    return 'compat:$epk:$_activeRoomId';
  }

  Future<void> _appendTranscriptEvent(TranscriptEvent event) =>
      _appendTranscriptEvents(<TranscriptEvent>[event]);

  Future<void> _appendTranscriptEvents(Iterable<TranscriptEvent> events) async {
    final sessionId = _activeTranscriptSessionId();
    var changed = false;
    for (final event in events) {
      if (event.sessionId != sessionId) continue;
      if (_transcriptEventIds.add(event.eventId)) {
        _transcriptEvents.add(event);
        changed = true;
      }
    }
    if (!changed) return;
    final projection = deriveTranscriptProjection(
      sessionId: sessionId,
      events: _transcriptEvents,
    );
    _emitStreaming(projection.streaming);
    final turn = projection.turn;
    _setWorking(
      turn.status == TranscriptTurnStatus.working ||
          turn.status == TranscriptTurnStatus.streaming,
      replyTo: turn.replyTo,
    );
    await _writeProjectionDiff(projection);
  }

  Future<void> _writeProjectionDiff(TranscriptProjection projection) async {
    final epk = _activeEpk;
    if (epk == null) return;
    final room = _activeRoomId;
    final desired = <MessageRecord>[
      for (var i = 0; i < projection.messages.length; i++)
        _recordFromProjectedMessage(projection.messages[i], i),
    ];
    await _enqueue(() async {
      if (_activeEpk != epk || _activeRoomId != room) return;
      final box = await _boxes.msgsBox(epk, room);
      for (final k in box.keys.toList()) {
        if ((k as num).toInt() >= desired.length) {
          await box.delete(k);
        }
      }
      for (var i = 0; i < desired.length; i++) {
        final newJson = desired[i].toJson();
        final curRaw = box.get(i);
        final curNorm = curRaw == null
            ? null
            : jsonEncode(MessageRecord.fromJson(_coerce(curRaw)).toJson());
        if (curNorm != jsonEncode(newJson)) {
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
    });
  }

  MessageRecord _recordFromProjectedMessage(ChatMessage message, int seq) {
    final now = DateTime.now();
    return switch (message) {
      UserMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.user,
        text: message.text,
        image: message.image,
        pending: message.status == UserMsgStatus.pending,
        ts: now,
      ),
      AssistantMsg() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.assistant,
        text: message.text,
        ts: now,
      ),
      ToolEvent() => MessageRecord(
        id: message.id,
        seq: seq,
        role: MsgRole.tool,
        ts: now,
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
        ts: now,
      ),
    };
  }

  Future<void> _applyHistory(SessionHistory h) async {
    final epk = _activeEpk;
    if (epk == null) return;
    final room = _activeRoomId;
    final incomingStartedAt = h.sessionStartedAt;

    if (_acceptedSessionStartedAtHighWater != null &&
        incomingStartedAt < _acceptedSessionStartedAtHighWater!) {
      return;
    }

    final sessionId = _activeTranscriptSessionId();
    await _seedPendingTranscriptEvents(epk, room, sessionId);
    await _appendTranscriptEvents(
      _historyToTranscriptEvents(h.events, sessionId),
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

  Future<void> _seedPendingTranscriptEvents(
    String epk,
    String room,
    String sessionId,
  ) async {
    final box = await _boxes.msgsBox(epk, room);
    final pending = <TranscriptEvent>[];
    for (final value in box.values) {
      final record = MessageRecord.fromJson(_coerce(value));
      if (record.role != MsgRole.user || !record.pending) continue;
      pending.add(
        UserMessageSubmitted(
          eventId: 'local:user_submitted:${record.id}',
          sessionId: sessionId,
          ts: record.ts,
          clientMessageId: record.id,
          text: record.text,
          image: record.image,
        ),
      );
    }
    await _appendTranscriptEvents(pending);
  }

  Iterable<TranscriptEvent> _historyToTranscriptEvents(
    List<SessionHistoryEvent> events,
    String sessionId,
  ) sync* {
    for (final e in events) {
      final ts = DateTime.fromMillisecondsSinceEpoch(e.ts);
      switch (e) {
        case UserInputEvt(:final id, :final text, :final image):
          yield UserMessageConfirmed(
            eventId: 'history:user_confirmed:$id',
            sessionId: sessionId,
            ts: ts,
            clientMessageId: id,
            text: text,
            image: image == null
                ? null
                : MessageImage(data: image.data, mime: image.mime),
          );
        case AgentMessageEvt(:final inReplyTo, :final text):
          yield AssistantMessageCommitted(
            eventId: 'history:assistant_committed:$inReplyTo:${e.ts}',
            sessionId: sessionId,
            ts: ts,
            messageId: 'agent_history_${inReplyTo}_${e.ts}',
            replyTo: inReplyTo,
            text: text,
          );
        case ToolRequestEvt(:final toolCallId, :final tool, :final args):
          yield ToolRequested(
            eventId: 'history:tool_requested:$toolCallId',
            sessionId: sessionId,
            ts: ts,
            toolCallId: toolCallId,
            tool: tool,
            args: args,
          );
        case ToolResultEvt(:final toolCallId, :final result, :final error):
          yield ToolFinished(
            eventId: 'history:tool_finished:$toolCallId',
            sessionId: sessionId,
            ts: ts,
            toolCallId: toolCallId,
            result: result,
            error: error,
          );
        case CompactionEvt(:final summary, :final tokensBefore):
          yield CompactionRecorded(
            eventId: 'history:compaction:${e.ts}',
            sessionId: sessionId,
            ts: ts,
            summary: summary,
            tokensBefore: tokensBefore,
          );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Box write helpers (all serialised through _enqueue)
  // ---------------------------------------------------------------------------

  String _key(MsgRole role, String id) => '${role.name}:$id';

  Future<void> _loadIndex() {
    final epk = _activeEpk;
    if (epk == null) return Future<void>.value();
    final room = _activeRoomId;
    return _enqueue(() async {
      if (_activeEpk != epk || _activeRoomId != room) return;
      final box = await _boxes.msgsBox(epk, room);
      final idx = _boxes.sessionsIndexBox();
      final indexRaw = idx.get(LocalBoxes.sessionKey(epk, room));
      _acceptedSessionStartedAtHighWater = indexRaw is Map<String, dynamic>
          ? SessionIndexRecord.fromJson(
              indexRaw,
            ).sessionStartedAt?.millisecondsSinceEpoch
          : indexRaw is Map
          ? SessionIndexRecord.fromJson(
              indexRaw.cast<String, dynamic>(),
            ).sessionStartedAt?.millisecondsSinceEpoch
          : null;
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

  Future<void> _upsert(
    MsgRole role,
    String id,
    MessageRecord Function(int seq, MessageRecord? existing) build,
  ) {
    final epk = _activeEpk;
    if (epk == null) return Future<void>.value();
    final room = _activeRoomId;
    return _enqueue(() async {
      final active = _activeEpk == epk && _activeRoomId == room;
      if (!active) return;
      final box = await _boxes.msgsBox(epk, room);
      final mapKey = _key(role, id);
      final existingSeq = _idToSeq[mapKey];
      if (existingSeq != null) {
        final existing = MessageRecord.fromJson(_coerce(box.get(existingSeq)));
        await box.put(existingSeq, build(existingSeq, existing).toJson());
      } else {
        final seq = _nextSeq++;
        await box.put(seq, build(seq, null).toJson());
        _idToSeq[mapKey] = seq;
      }
    });
  }

  Future<void> _removePendingById(String id) {
    final epk = _activeEpk;
    if (epk == null) return Future<void>.value();
    final room = _activeRoomId;
    return _enqueue(() async {
      if (_activeEpk != epk || _activeRoomId != room) return;
      final box = await _boxes.msgsBox(epk, room);
      for (final role in MsgRole.values) {
        final key = _key(role, id);
        final seq = _idToSeq[key];
        if (seq == null) continue;
        final raw = box.get(seq);
        if (raw == null) {
          _idToSeq.remove(key);
          continue;
        }
        final existing = MessageRecord.fromJson(_coerce(raw));
        if (!existing.pending) continue;
        _idToSeq.remove(key);
        await box.delete(seq);
      }
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

  /// Single source of "the active session is working". Drives the in-memory
  /// flag/stream (chat pill) AND the durable session index (Home dot).
  void _setQueuedText(String? text) {
    if (_queuedText == text) return;
    _queuedText = text;
    if (!_queuedController.isClosed) _queuedController.add(text);
  }

  void _setWorking(bool on, {String? preview, String? replyTo}) {
    _setActivity(
      on ? SessionActivity.working : SessionActivity.idle,
      preview: preview,
    );
    // Snapshot nullable field once; Dart won't promote mutable fields safely.
    final epk = _activeEpk;
    if (epk != null) {
      _conn.markRoomWorking(epk, _activeRoomId, on);
    }
    if (on) {
      if (replyTo != null) _workingReplyTo = replyTo;
    } else {
      _workingReplyTo = null;
    }
    if (_working == on) return;
    _working = on;
    if (!_workingController.isClosed) _workingController.add(on);
  }

  void _updateIndex(SessionIndexRecord Function(SessionIndexRecord cur) build) {
    final epk = _activeEpk;
    if (epk == null) return;
    final room = _activeRoomId;
    // ignore: discarded_futures
    _enqueue(() async {
      final idx = _boxes.sessionsIndexBox();
      final key = LocalBoxes.sessionKey(epk, room);
      final raw = idx.get(key);
      final cur = raw is Map
          ? SessionIndexRecord.fromJson(raw.cast<String, dynamic>())
          : SessionIndexRecord(epk: epk, roomId: room);
      await idx.put(key, build(cur).toJson());
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
        LocalBoxes.sessionKey(epk, room),
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

  static String _preview(String text, MessageImage? image) {
    if (text.isEmpty && image != null) return '📷 Image';
    return text.length <= 80 ? text : '${text.substring(0, 80)}…';
  }

  static String _newId() => 'cli_${uuid7()}';

  @override
  void dispose() {
    _flushTimer?.cancel();
    _syncDebounce?.cancel();
    _cancelAllSendTimers();
    _connSub?.cancel();
    _msgSub?.cancel();
    _roomsSub?.cancel();
    _presenceSub?.cancel();
    _streamingController.close();
    _eventController.close();
    _workingController.close();
    _queuedController.close();
  }
}
