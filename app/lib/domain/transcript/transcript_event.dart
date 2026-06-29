import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart' show UserMessageStreamingBehavior, Usage;

sealed class TranscriptEvent {
  const TranscriptEvent({
    required this.eventId,
    required this.sessionId,
    required this.ts,
    this.turnId,
  });

  final String eventId;
  final String sessionId;
  final DateTime ts;
  final String? turnId;
}

final class UserMessageSubmitted extends TranscriptEvent {
  const UserMessageSubmitted({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.text,
    this.image,
  });

  final String clientMessageId;
  final String text;
  final MessageImage? image;
}

final class UserMessageConfirmed extends TranscriptEvent {
  const UserMessageConfirmed({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.text,
    this.image,
    this.streamingBehavior,
  });

  final String clientMessageId;
  final String text;
  final MessageImage? image;
  final UserMessageStreamingBehavior? streamingBehavior;
}

final class UserMessageFailed extends TranscriptEvent {
  const UserMessageFailed({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.code,
    required this.message,
  });

  final String clientMessageId;
  final String code;
  final String message;
}

final class AssistantDeltaReceived extends TranscriptEvent {
  const AssistantDeltaReceived({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.replyTo,
    required this.delta,
  });

  final String replyTo;
  final String delta;
}

final class AssistantMessageCommitted extends TranscriptEvent {
  const AssistantMessageCommitted({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.messageId,
    required this.replyTo,
    required this.text,
    this.usage,
  });

  final String messageId;
  final String replyTo;
  final String text;
  final Usage? usage;
}

final class AssistantDoneReceived extends TranscriptEvent {
  const AssistantDoneReceived({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.replyTo,
    this.usage,
  });

  final String replyTo;
  final Usage? usage;
}

final class ToolRequested extends TranscriptEvent {
  const ToolRequested({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.toolCallId,
    required this.tool,
    required this.args,
  });

  final String toolCallId;
  final String tool;
  final Map<String, Object?> args;
}

final class ToolFinished extends TranscriptEvent {
  const ToolFinished({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.toolCallId,
    this.result,
    this.error,
  });

  final String toolCallId;
  final Object? result;
  final String? error;
}

final class CompactionRecorded extends TranscriptEvent {
  const CompactionRecorded({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.summary,
    this.tokensBefore,
  });

  final String summary;
  final int? tokensBefore;
}
