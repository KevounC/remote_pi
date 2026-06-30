import 'package:app/domain/session_state.dart';
import 'package:app/protocol/protocol.dart'
    show
        AgentMessageEvt,
        CompactionEvt,
        SessionHistoryEvent,
        ToolRequestEvt,
        ToolResultEvt,
        Usage,
        UserInputEvt,
        UserMessageStreamingBehavior;

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

Iterable<TranscriptEvent> historyToTranscriptEvents(
  Iterable<SessionHistoryEvent> events, {
  required String sessionId,
}) sync* {
  for (final event in events) {
    final ts = DateTime.fromMillisecondsSinceEpoch(event.ts);
    switch (event) {
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
          eventId: 'history:assistant_committed:$inReplyTo:${event.ts}',
          sessionId: sessionId,
          ts: ts,
          messageId: 'agent_history_${inReplyTo}_${event.ts}',
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
          args: _objectMap(args),
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
          eventId: 'history:compaction:${event.ts}',
          sessionId: sessionId,
          ts: ts,
          summary: summary,
          tokensBefore: tokensBefore,
        );
    }
  }
}

Map<String, Object?> _objectMap(Object? raw) {
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
