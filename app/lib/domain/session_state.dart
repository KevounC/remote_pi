// Session domain model — immutable state for the active chat session.
// Lives in domain/ → no Flutter, no network, no storage.

import 'package:app/data/transport/connection_manager.dart';

// ---------------------------------------------------------------------------
// ChatMessage — sealed union of message variants in the conversation history
// ---------------------------------------------------------------------------

sealed class ChatMessage {
  final String id;
  const ChatMessage({required this.id});
}

class UserMsg extends ChatMessage {
  final String text;
  const UserMsg({required super.id, required this.text});

  @override
  bool operator ==(Object other) =>
      other is UserMsg && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

class AssistantMsg extends ChatMessage {
  final String text;
  const AssistantMsg({required super.id, required this.text});

  @override
  bool operator ==(Object other) =>
      other is AssistantMsg && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

class ToolEvent extends ChatMessage {
  final String toolCallId;
  final String tool;
  final dynamic args;
  final ToolEventStatus status;
  final dynamic result;
  final String? error;

  const ToolEvent({
    required super.id,
    required this.toolCallId,
    required this.tool,
    required this.args,
    this.status = ToolEventStatus.pending,
    this.result,
    this.error,
  });

  ToolEvent copyWith({
    ToolEventStatus? status,
    dynamic result,
    String? error,
  }) =>
      ToolEvent(
        id: id,
        toolCallId: toolCallId,
        tool: tool,
        args: args,
        status: status ?? this.status,
        result: result ?? this.result,
        error: error ?? this.error,
      );

  @override
  bool operator ==(Object other) =>
      other is ToolEvent &&
      other.id == id &&
      other.toolCallId == toolCallId &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, toolCallId, status);
}

enum ToolEventStatus { pending, allowed, denied, expired, completed }

// ---------------------------------------------------------------------------
// StreamingMessage — accumulated deltas while the assistant is typing
// ---------------------------------------------------------------------------

class StreamingMessage {
  final String inReplyTo; // id of the UserMsg being answered
  final String buffer;

  const StreamingMessage({required this.inReplyTo, this.buffer = ''});

  StreamingMessage appendDelta(String delta) =>
      StreamingMessage(inReplyTo: inReplyTo, buffer: buffer + delta);

  @override
  bool operator ==(Object other) =>
      other is StreamingMessage &&
      other.inReplyTo == inReplyTo &&
      other.buffer == buffer;

  @override
  int get hashCode => Object.hash(inReplyTo, buffer);
}

// ---------------------------------------------------------------------------
// SessionState — the full observable state of the chat session
// ---------------------------------------------------------------------------

class SessionState {
  final ConnectionStatus connection;
  final List<ChatMessage> messages;
  final StreamingMessage? streaming;

  const SessionState({
    this.connection = const StatusNoPeer(),
    this.messages = const [],
    this.streaming,
  });

  SessionState copyWith({
    ConnectionStatus? connection,
    List<ChatMessage>? messages,
    StreamingMessage? streaming,
    bool clearStreaming = false,
  }) =>
      SessionState(
        connection: connection ?? this.connection,
        messages: messages ?? this.messages,
        streaming: clearStreaming ? null : (streaming ?? this.streaming),
      );

  @override
  bool operator ==(Object other) =>
      other is SessionState &&
      other.connection == connection &&
      other.messages == messages &&
      other.streaming == streaming;

  @override
  int get hashCode => Object.hash(connection, messages, streaming);
}
