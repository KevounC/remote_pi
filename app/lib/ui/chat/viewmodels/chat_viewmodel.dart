import 'dart:async';

import 'package:app/data/repositories/i_session_repository.dart';
import 'package:app/data/transport/connection_manager.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/pairing/storage.dart';
import 'package:app/protocol/protocol.dart';
import 'package:app/ui/chat/states/chat_state.dart';
import 'package:app/ui/core/viewmodel/viewmodel.dart';

class ChatViewModel extends ViewModel<ChatState> {
  final ISessionRepository _repo;
  StreamSubscription? _sub;

  ChatViewModel(ISessionRepository repo)
    : _repo = repo,
      super(const ChatConnecting()) {
    _sub = _repo.sessionStream.listen(_onSession);
    _repo.boot();
  }

  // ---------------------------------------------------------------------------
  // Actions — called from UI
  // ---------------------------------------------------------------------------

  Future<void> sendMessage(String text) => _repo.sendMessage(text);

  Future<void> cancel(String targetId) => _repo.cancel(targetId);

  Future<void> approveTool(String toolCallId, ApproveDecision decision) =>
      _repo.approveTool(toolCallId, decision);

  Future<void> connectTo(PeerRecord peer) => _repo.connectTo(peer);

  // ---------------------------------------------------------------------------
  // Session → ChatState translation
  // ---------------------------------------------------------------------------

  void _onSession(SessionState s) {
    emit(_toChat(s));
  }

  static ChatState _toChat(SessionState s) {
    return switch (s.connection) {
      StatusNoPeer() => const ChatNoPeer(),
      StatusConnecting() => const ChatConnecting(),
      StatusOnline() => ChatReady(
        messages: s.messages,
        streaming: s.streaming,
      ),
      StatusRetrying() => ChatReady(
        messages: s.messages,
        streaming: s.streaming,
        isOffline: true,
      ),
      StatusOffline(:final canRetry, :final reason) when !canRetry =>
        ChatFatalError(reason),
      StatusOffline() => ChatReady(
        messages: s.messages,
        streaming: s.streaming,
        isOffline: true,
      ),
    };
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
