sealed class CockpitTranscriptEvent {
  const CockpitTranscriptEvent({
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

final class CockpitUserMessageSubmitted extends CockpitTranscriptEvent {
  const CockpitUserMessageSubmitted({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.text,
  });

  final String clientMessageId;
  final String text;
}

final class CockpitUserMessageConfirmed extends CockpitTranscriptEvent {
  const CockpitUserMessageConfirmed({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.clientMessageId,
    required this.text,
  });

  final String clientMessageId;
  final String text;
}

final class CockpitUserMessageFailed extends CockpitTranscriptEvent {
  const CockpitUserMessageFailed({
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

final class CockpitAssistantDeltaReceived extends CockpitTranscriptEvent {
  const CockpitAssistantDeltaReceived({
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

final class CockpitAssistantMessageCommitted extends CockpitTranscriptEvent {
  const CockpitAssistantMessageCommitted({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.messageId,
    required this.replyTo,
    required this.text,
  });

  final String messageId;
  final String replyTo;
  final String text;
}

final class CockpitAssistantDoneReceived extends CockpitTranscriptEvent {
  const CockpitAssistantDoneReceived({
    required super.eventId,
    required super.sessionId,
    required super.ts,
    super.turnId,
    required this.replyTo,
  });

  final String replyTo;
}

final class CockpitToolRequested extends CockpitTranscriptEvent {
  const CockpitToolRequested({
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

final class CockpitToolFinished extends CockpitTranscriptEvent {
  const CockpitToolFinished({
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

final class CockpitCompactionRecorded extends CockpitTranscriptEvent {
  const CockpitCompactionRecorded({
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

enum CockpitTranscriptTurnStatus { idle, working, streaming, error }

final class CockpitTranscriptTurnView {
  const CockpitTranscriptTurnView({
    required this.status,
    this.replyTo,
    this.error,
  });

  final CockpitTranscriptTurnStatus status;
  final String? replyTo;
  final String? error;
}
