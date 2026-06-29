import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/protocol/protocol.dart' show Usage, UserMessageStreamingBehavior;

final class TranscriptEventRecord {
  const TranscriptEventRecord({
    required this.eventId,
    required this.seq,
    required this.sessionId,
    required this.kind,
    required this.ts,
    required this.payload,
  });

  final String eventId;
  final int seq;
  final String sessionId;
  final String kind;
  final int ts;
  final Map<String, Object?> payload;

  factory TranscriptEventRecord.fromEvent(TranscriptEvent event, int seq) {
    return TranscriptEventRecord(
      eventId: event.eventId,
      seq: seq,
      sessionId: event.sessionId,
      kind: _kindOf(event),
      ts: event.ts.millisecondsSinceEpoch,
      payload: _payloadOf(event),
    );
  }

  factory TranscriptEventRecord.fromJson(Map<String, Object?> json) {
    final eventId = _requireString(json, 'event_id');
    final seq = _requireInt(json, 'seq');
    final sessionId = _requireString(json, 'session_id');
    final kind = _requireString(json, 'kind');
    final ts = _requireInt(json, 'ts');
    final payload = _objectMap(json['payload']);
    _eventFromParts(eventId, sessionId, kind, ts, payload); // fail fast on kind/payload drift.
    return TranscriptEventRecord(
      eventId: eventId,
      seq: seq,
      sessionId: sessionId,
      kind: kind,
      ts: ts,
      payload: payload,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'event_id': eventId,
        'seq': seq,
        'session_id': sessionId,
        'kind': kind,
        'ts': ts,
        'payload': payload,
      };

  TranscriptEvent toEvent() => _eventFromParts(eventId, sessionId, kind, ts, payload);
}

String _kindOf(TranscriptEvent event) => switch (event) {
      UserMessageSubmitted() => 'user_submitted',
      UserMessageConfirmed() => 'user_confirmed',
      UserMessageFailed() => 'user_failed',
      AssistantDeltaReceived() => 'assistant_delta',
      AssistantMessageCommitted() => 'assistant_message',
      AssistantDoneReceived() => 'assistant_done',
      ToolRequested() => 'tool_requested',
      ToolFinished() => 'tool_finished',
      CompactionRecorded() => 'compaction',
    };

Map<String, Object?> _payloadOf(TranscriptEvent event) {
  final base = <String, Object?>{
    if (event.turnId != null) 'turn_id': event.turnId,
  };
  return switch (event) {
    UserMessageSubmitted() => {
        ...base,
        'client_message_id': event.clientMessageId,
        'text': event.text,
        if (event.image != null) 'image': _imageToJson(event.image!),
      },
    UserMessageConfirmed() => {
        ...base,
        'client_message_id': event.clientMessageId,
        'text': event.text,
        if (event.image != null) 'image': _imageToJson(event.image!),
        if (event.streamingBehavior != null) 'streaming_behavior': event.streamingBehavior!.name,
      },
    UserMessageFailed() => {
        ...base,
        'client_message_id': event.clientMessageId,
        'code': event.code,
        'message': event.message,
      },
    AssistantDeltaReceived() => {
        ...base,
        'reply_to': event.replyTo,
        'delta': event.delta,
      },
    AssistantMessageCommitted() => {
        ...base,
        'message_id': event.messageId,
        'reply_to': event.replyTo,
        'text': event.text,
        if (event.usage != null) 'usage': _usageToJson(event.usage!),
      },
    AssistantDoneReceived() => {
        ...base,
        'reply_to': event.replyTo,
        if (event.usage != null) 'usage': _usageToJson(event.usage!),
      },
    ToolRequested() => {
        ...base,
        'tool_call_id': event.toolCallId,
        'tool': event.tool,
        'args': event.args,
      },
    ToolFinished() => {
        ...base,
        'tool_call_id': event.toolCallId,
        if (event.result != null) 'result': event.result,
        if (event.error != null) 'error': event.error,
      },
    CompactionRecorded() => {
        ...base,
        'summary': event.summary,
        if (event.tokensBefore != null) 'tokens_before': event.tokensBefore,
      },
  };
}

TranscriptEvent _eventFromParts(
  String eventId,
  String sessionId,
  String kind,
  int ts,
  Map<String, Object?> payload,
) {
  final time = DateTime.fromMillisecondsSinceEpoch(ts);
  final turnId = payload['turn_id'] as String?;
  return switch (kind) {
    'user_submitted' => UserMessageSubmitted(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        clientMessageId: _requireString(payload, 'client_message_id'),
        text: _requireString(payload, 'text'),
        image: _optionalImage(payload['image']),
      ),
    'user_confirmed' => UserMessageConfirmed(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        clientMessageId: _requireString(payload, 'client_message_id'),
        text: _requireString(payload, 'text'),
        image: _optionalImage(payload['image']),
        streamingBehavior: _optionalStreamingBehavior(payload['streaming_behavior']),
      ),
    'user_failed' => UserMessageFailed(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        clientMessageId: _requireString(payload, 'client_message_id'),
        code: _requireString(payload, 'code'),
        message: _requireString(payload, 'message'),
      ),
    'assistant_delta' => AssistantDeltaReceived(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        replyTo: _requireString(payload, 'reply_to'),
        delta: _requireString(payload, 'delta'),
      ),
    'assistant_message' => AssistantMessageCommitted(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        messageId: _requireString(payload, 'message_id'),
        replyTo: _requireString(payload, 'reply_to'),
        text: _requireString(payload, 'text'),
        usage: _optionalUsage(payload['usage']),
      ),
    'assistant_done' => AssistantDoneReceived(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        replyTo: _requireString(payload, 'reply_to'),
        usage: _optionalUsage(payload['usage']),
      ),
    'tool_requested' => ToolRequested(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        toolCallId: _requireString(payload, 'tool_call_id'),
        tool: _requireString(payload, 'tool'),
        args: _objectMap(payload['args']),
      ),
    'tool_finished' => ToolFinished(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        toolCallId: _requireString(payload, 'tool_call_id'),
        result: payload['result'],
        error: payload['error'] as String?,
      ),
    'compaction' => CompactionRecorded(
        eventId: eventId,
        sessionId: sessionId,
        ts: time,
        turnId: turnId,
        summary: _requireString(payload, 'summary'),
        tokensBefore: payload['tokens_before'] as int?,
      ),
    _ => throw FormatException('Unknown transcript event kind: $kind'),
  };
}

String _requireString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Transcript event field "$key" must be a string');
}

int _requireInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Transcript event field "$key" must be an int');
}

Map<String, Object?> _objectMap(Object? value) {
  if (value == null) return <String, Object?>{};
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) {
      if (key is! String) throw const FormatException('Transcript event map keys must be strings');
      return MapEntry(key, value as Object?);
    });
  }
  throw const FormatException('Transcript event payload must be an object');
}

Map<String, Object?> _imageToJson(MessageImage image) => <String, Object?>{
      'data': image.data,
      'mime': image.mime,
    };

MessageImage? _optionalImage(Object? value) {
  if (value == null) return null;
  final json = _objectMap(value);
  return MessageImage(
    data: _requireString(json, 'data'),
    mime: _requireString(json, 'mime'),
  );
}

Map<String, Object?> _usageToJson(Usage usage) => <String, Object?>{
      'input_tokens': usage.inputTokens,
      'output_tokens': usage.outputTokens,
    };

Usage? _optionalUsage(Object? value) {
  if (value == null) return null;
  final json = _objectMap(value);
  return Usage(
    inputTokens: _requireInt(json, 'input_tokens'),
    outputTokens: _requireInt(json, 'output_tokens'),
  );
}

UserMessageStreamingBehavior? _optionalStreamingBehavior(Object? value) {
  if (value == null) return null;
  if (value is String) return UserMessageStreamingBehavior.values.byName(value);
  throw const FormatException('streaming_behavior must be a string');
}
