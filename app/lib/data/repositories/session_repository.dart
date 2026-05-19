// SessionRepository — orchestrates ConnectionManager + PeerChannel.
//
// Exposes a Stream<SessionState> that combines:
//   • connection status changes
//   • incoming ServerMessages (agent chunks, tool requests, etc.)
//
// Provides action methods (sendMessage, cancel, approveTool) that the
// ChatViewModel calls.

import 'dart:async';

import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/transport/channel.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/contracts/repository.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';

class SessionRepository extends Repository implements ISessionRepository {
  final ConnectionManager _conn;

  final _stateController = StreamController<SessionState>.broadcast();
  SessionState _state = const SessionState();

  StreamSubscription? _connSub;
  StreamSubscription? _msgSub;

  // 16ms streaming buffer — coalesces AgentChunk deltas per video frame (Q2).
  final StringBuffer _chunkBuffer = StringBuffer();
  String _chunkReplyTo = '';
  Timer? _flushTimer;

  SessionRepository(this._conn) {
    _connSub = _conn.statusStream.listen(_onStatusChange);
  }

  @override
  SessionState get current => _state;
  @override
  Stream<SessionState> get sessionStream => _stateController.stream;

  @override
  Future<void> boot() => _conn.boot();

  @override
  Future<void> connectTo(PeerRecord peer) => _conn.connectTo(peer);

  @override
  void adoptChannel(IChannel channel, PeerRecord peer) =>
      _conn.adopt(channel, peer);

  @override
  Future<void> disconnect() => _conn.disconnect();

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  @override
  Future<void> sendMessage(String text) async {
    final ch = _conn.channel;
    if (ch == null) return;

    final msg = UserMessage(id: _newId(), text: text);
    _emit(
      _state.copyWith(
        messages: [..._state.messages, UserMsg(id: msg.id, text: text)],
        streaming: StreamingMessage(inReplyTo: msg.id),
      ),
    );
    await ch.send(msg);
  }

  @override
  Future<void> cancel(String targetId) async {
    final ch = _conn.channel;
    if (ch == null) return;
    await ch.send(Cancel(id: _newId(), targetId: targetId));
  }

  @override
  Future<void> approveTool(
    String toolCallId,
    ApproveDecision decision,
  ) async {
    final ch = _conn.channel;
    if (ch == null) return;
    await ch.send(
      ApproveTool(id: _newId(), toolCallId: toolCallId, decision: decision),
    );
    _updateTool(
      toolCallId,
      decision == ApproveDecision.allow
          ? ToolEventStatus.allowed
          : ToolEventStatus.denied,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal event handlers
  // ---------------------------------------------------------------------------

  void _onStatusChange(ConnectionStatus s) {
    _msgSub?.cancel();
    _msgSub = null;

    if (s is StatusOnline) {
      _msgSub = s.channel.serverMessages.listen(
        _onServerMessage,
        onDone: () {},
      );
    }
    _emit(_state.copyWith(connection: s));
  }

  void _onServerMessage(ServerMessage msg) {
    switch (msg) {
      case AgentChunk(:final inReplyTo, :final delta):
        _chunkBuffer.write(delta);
        _chunkReplyTo = inReplyTo;
        _flushTimer?.cancel();
        _flushTimer = Timer(const Duration(milliseconds: 16), _flushChunks);

      case AgentDone(:final inReplyTo):
        final cur = _state.streaming;
        if (cur != null && cur.inReplyTo == inReplyTo && cur.buffer.isNotEmpty) {
          _emit(
            _state.copyWith(
              messages: [
                ..._state.messages,
                AssistantMsg(id: inReplyTo, text: cur.buffer),
              ],
              clearStreaming: true,
            ),
          );
        } else {
          _emit(_state.copyWith(clearStreaming: true));
        }

      case ToolRequest(:final toolCallId, :final tool, :final args):
        final event = ToolEvent(
          id: toolCallId,
          toolCallId: toolCallId,
          tool: tool,
          args: args,
        );
        _emit(_state.copyWith(messages: [..._state.messages, event]));

      case ToolResult(:final toolCallId, :final result, :final error):
        _updateTool(
          toolCallId,
          error != null ? ToolEventStatus.denied : ToolEventStatus.completed,
          result: result,
          error: error,
        );

      case Cancelled(:final targetId):
        _emit(
          _state.copyWith(
            messages: [
              ..._state.messages.where((m) => m.id != targetId),
            ],
            clearStreaming: true,
          ),
        );

      case Pong():
        // Ping/pong handled at ConnectionManager level; nothing to do here.
        break;

      case PairOk():
      case PairError():
        // Pairing messages belong to the pair flow; ignore here — the
        // pairing transport is consumed by PairingViewModel before this
        // channel is adopted.
        break;

      case ErrorMessage(:final code, :final message):
        // Expose as a special AssistantMsg so the UI can show it.
        _emit(
          _state.copyWith(
            messages: [
              ..._state.messages,
              AssistantMsg(id: _newId(), text: '⚠ $code: $message'),
            ],
          ),
        );
    }
  }

  void _flushChunks() {
    if (_chunkBuffer.isEmpty) return;
    final delta = _chunkBuffer.toString();
    _chunkBuffer.clear();
    final cur = _state.streaming;
    if (cur != null && cur.inReplyTo == _chunkReplyTo) {
      _emit(_state.copyWith(streaming: cur.appendDelta(delta)));
    } else {
      _emit(
        _state.copyWith(
          streaming: StreamingMessage(inReplyTo: _chunkReplyTo, buffer: delta),
        ),
      );
    }
  }

  void _updateTool(
    String toolCallId,
    ToolEventStatus status, {
    dynamic result,
    String? error,
  }) {
    final updated = _state.messages.map((m) {
      if (m is ToolEvent && m.toolCallId == toolCallId) {
        return m.copyWith(status: status, result: result, error: error);
      }
      return m;
    }).toList();
    _emit(_state.copyWith(messages: updated));
  }

  void _emit(SessionState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _flushTimer?.cancel();
    _connSub?.cancel();
    _msgSub?.cancel();
    _conn.dispose();
    _stateController.close();
  }

  static int _counter = 0;
  static String _newId() => 'cli_${++_counter}';
}
