import 'package:app/domain/session_state.dart';

// Sealed state for ChatViewModel.
// Switch exhaustively in ChatPage.build().

sealed class ChatState {
  const ChatState();
}

// No peer paired yet — show QR scanner redirect.
class ChatNoPeer extends ChatState {
  const ChatNoPeer();
}

// Establishing connection after boot or reconnect.
class ChatConnecting extends ChatState {
  const ChatConnecting();
}

// Connected and ready.
class ChatReady extends ChatState {
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;
  final bool isOffline; // true → input disabled, banner visible

  const ChatReady({
    required this.messages,
    this.streaming,
    this.isOffline = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ChatReady &&
      other.messages == messages &&
      other.streaming == streaming &&
      other.isOffline == isOffline;

  @override
  int get hashCode => Object.hash(messages, streaming, isOffline);
}

// Permanent offline — fingerprint mismatch → must re-pair.
class ChatFatalError extends ChatState {
  final String message;
  const ChatFatalError(this.message);

  @override
  bool operator ==(Object other) =>
      other is ChatFatalError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
