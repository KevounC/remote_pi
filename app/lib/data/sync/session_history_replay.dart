import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/protocol/protocol.dart'
    show
        AgentMessageEvt,
        CompactionEvt,
        SessionHistory,
        SessionHistoryEvent,
        ToolRequestEvt,
        ToolResultEvt,
        UserInputEvt;

/// Converts an authoritative `session_history` wire payload into canonical
/// transcript events without touching storage or UI state.
///
/// Event ids are derived only from stable server facts in each history event.
/// The outer `SessionHistory.inReplyTo` request id is deliberately ignored so
/// reconnects and repeated sync requests append/dedupe the same event ids.
List<TranscriptEvent> sessionHistoryToTranscriptEvents({
  required SessionHistory history,
  required String sessionId,
}) {
  if (sessionId.isEmpty) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'SessionHistory replay requires a canonical session id',
    );
  }

  return <TranscriptEvent>[
    for (final event in history.events)
      sessionHistoryEventToTranscriptEvent(event, sessionId: sessionId),
  ];
}

TranscriptEvent sessionHistoryEventToTranscriptEvent(
  SessionHistoryEvent event, {
  required String sessionId,
}) {
  if (sessionId.isEmpty) {
    throw ArgumentError.value(
      sessionId,
      'sessionId',
      'SessionHistory replay requires a canonical session id',
    );
  }

  final ts = DateTime.fromMillisecondsSinceEpoch(event.ts);
  return switch (event) {
    UserInputEvt(:final id, :final text, :final image) => UserMessageConfirmed(
      eventId: serverReplayEventId(sessionId, 'user_input', id, event.ts),
      sessionId: sessionId,
      ts: ts,
      clientMessageId: id,
      text: text,
      image: image == null
          ? null
          : MessageImage(data: image.data, mime: image.mime),
    ),
    AgentMessageEvt(:final inReplyTo, :final text) => AssistantMessageCommitted(
      eventId: serverReplayEventId(
        sessionId,
        'agent_message',
        inReplyTo,
        event.ts,
      ),
      sessionId: sessionId,
      ts: ts,
      messageId: serverReplayMessageId(
        sessionId,
        'agent_message',
        inReplyTo,
        event.ts,
      ),
      replyTo: inReplyTo,
      text: text,
    ),
    ToolRequestEvt(:final toolCallId, :final tool, :final args) =>
      ToolRequested(
        eventId: serverReplayEventId(
          sessionId,
          'tool_request',
          toolCallId,
          event.ts,
        ),
        sessionId: sessionId,
        ts: ts,
        toolCallId: toolCallId,
        tool: tool,
        args: _objectMap(args),
      ),
    ToolResultEvt(:final toolCallId, :final result, :final error) =>
      ToolFinished(
        eventId: serverReplayEventId(
          sessionId,
          'tool_result',
          toolCallId,
          event.ts,
        ),
        sessionId: sessionId,
        ts: ts,
        toolCallId: toolCallId,
        result: result,
        error: error,
      ),
    CompactionEvt(:final summary, :final tokensBefore) => CompactionRecorded(
      eventId: serverReplayEventId(
        sessionId,
        'compaction',
        'compaction',
        event.ts,
      ),
      sessionId: sessionId,
      ts: ts,
      summary: summary,
      tokensBefore: tokensBefore,
    ),
  };
}

String serverReplayEventId(
  String sessionId,
  String historyType,
  String stableKey,
  int ts,
) => 'server:$sessionId:$historyType:$stableKey:$ts';

String serverReplayMessageId(
  String sessionId,
  String historyType,
  String stableKey,
  int ts,
) => 'server-message:$sessionId:$historyType:$stableKey:$ts';

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
