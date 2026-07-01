import 'dart:typed_data';

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
    this.images = const <Uint8List>[],
  });

  final String clientMessageId;
  final String text;
  final List<Uint8List> images;
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

final class CockpitThinkingDeltaReceived extends CockpitTranscriptEvent {
  const CockpitThinkingDeltaReceived({
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

/// Append-only local transcript event log with event-id dedupe.
///
/// `get_messages` snapshots and live RPC events both enter this seam. The UI
/// projection chooses a session slice at read time, so switching session/path
/// hides old events without making `_entries` the transcript source of truth.
final class CockpitTranscriptEventLog {
  final List<CockpitTranscriptEvent> _events = <CockpitTranscriptEvent>[];
  final Set<String> _seenEventIds = <String>{};

  bool get isEmpty => _events.isEmpty;

  void append(CockpitTranscriptEvent event) {
    if (!_seenEventIds.add(event.eventId)) return;
    _events.add(event);
  }

  void appendAll(Iterable<CockpitTranscriptEvent> events) {
    for (final event in events) {
      append(event);
    }
  }

  List<CockpitTranscriptEvent> forSession(String sessionId) => _events
      .where((event) => event.sessionId == sessionId)
      .toList(growable: false);

  void clear() {
    _events.clear();
    _seenEventIds.clear();
  }
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
