import 'dart:convert';
import 'dart:io';

import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = 'sess-a';
  final base = DateTime.utc(2026, 1, 1);

  UserMessageSubmitted submitted(
    String id,
    String text, {
    String s = session,
  }) => UserMessageSubmitted(
    eventId: 'local:$id',
    sessionId: s,
    ts: base,
    clientMessageId: id,
    text: text,
  );

  UserMessageConfirmed confirmed(
    String id,
    String text, {
    String s = session,
  }) => UserMessageConfirmed(
    eventId: 'server:user:$id',
    sessionId: s,
    ts: base,
    clientMessageId: id,
    text: text,
  );

  UserMessageFailed failed(String id, String message, {String s = session}) =>
      UserMessageFailed(
        eventId: 'local:failed:$id',
        sessionId: s,
        ts: base,
        clientMessageId: id,
        code: 'send_timeout',
        message: message,
      );

  test('local pending remains visible after authoritative replay prefix', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [submitted('cli_1', 'hello'), confirmed('server_old', 'older')],
    );

    expect(projection.messages, [
      const UserMsg(id: 'server_old', text: 'older'),
      const UserMsg(id: 'cli_1', text: 'hello', status: UserMsgStatus.pending),
    ]);
    expect(projection.turn.status, TranscriptTurnStatus.working);
  });

  test('authoritative same id confirms an optimistic send in place', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [submitted('cli_1', 'hello'), confirmed('cli_1', 'hello')],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
  });

  test('timeout is suppressed by late authoritative confirmation', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        submitted('cli_1', 'hello'),
        failed('cli_1', 'send timed out'),
        confirmed('cli_1', 'hello'),
      ],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
  });

  test(
    'timeout marks pending local send failed while no confirmation exists',
    () {
      final projection = deriveTranscriptProjection(
        sessionId: session,
        events: [
          submitted('cli_1', 'hello'),
          failed('cli_1', 'send timed out'),
        ],
      );

      expect(projection.messages, [
        const UserMsg(id: 'cli_1', text: 'hello', status: UserMsgStatus.failed),
      ]);
      expect(projection.turn.status, TranscriptTurnStatus.error);
    },
  );

  test('foreign device authoritative message appears in server prefix', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [confirmed('other_1', 'from another owner')],
    );

    expect(projection.messages, [
      const UserMsg(id: 'other_1', text: 'from another owner'),
    ]);
  });

  test('tool request and result collapse into one projected tool row', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        ToolRequested(
          eventId: 'server:tool:req:t1',
          sessionId: session,
          ts: base,
          toolCallId: 't1',
          tool: 'Bash',
          args: const {'command': 'pwd'},
        ),
        ToolFinished(
          eventId: 'server:tool:done:t1',
          sessionId: session,
          ts: base,
          toolCallId: 't1',
          result: 'ok',
        ),
      ],
    );

    expect(projection.messages, [
      const ToolEvent(
        id: 't1',
        toolCallId: 't1',
        tool: 'Bash',
        args: {'command': 'pwd'},
        status: ToolEventStatus.completed,
        result: 'ok',
      ),
    ]);
    final tool = projection.messages.single as ToolEvent;
    expect(tool.tool, 'Bash');
    expect(tool.args, {'command': 'pwd'});
    expect(tool.status, ToolEventStatus.completed);
    expect(tool.result, 'ok');
    expect(tool.error, isNull);
  });

  test('streaming deltas finalize on committed assistant message', () {
    final streaming = deriveTranscriptProjection(
      sessionId: session,
      events: [
        AssistantDeltaReceived(
          eventId: 'server:delta:1',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
          delta: 'he',
        ),
        AssistantDeltaReceived(
          eventId: 'server:delta:2',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
          delta: 'llo',
        ),
      ],
    );

    expect(
      streaming.streaming,
      const StreamingMessage(inReplyTo: 'cli_1', buffer: 'hello'),
    );
    expect(streaming.turn.status, TranscriptTurnStatus.streaming);

    final committed = deriveTranscriptProjection(
      sessionId: session,
      events: [
        ...[
          AssistantDeltaReceived(
            eventId: 'server:delta:1',
            sessionId: session,
            ts: base,
            replyTo: 'cli_1',
            delta: 'he',
          ),
          AssistantDeltaReceived(
            eventId: 'server:delta:2',
            sessionId: session,
            ts: base,
            replyTo: 'cli_1',
            delta: 'llo',
          ),
        ],
        AssistantMessageCommitted(
          eventId: 'server:assistant:a1',
          sessionId: session,
          ts: base,
          messageId: 'a1',
          replyTo: 'cli_1',
          text: 'hello',
        ),
      ],
    );

    expect(committed.streaming, isNull);
    expect(committed.messages, [const AssistantMsg(id: 'a1', text: 'hello')]);
    expect(committed.turn.status, TranscriptTurnStatus.idle);
  });

  test('assistant done clears streaming and converges idle', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        AssistantDeltaReceived(
          eventId: 'server:delta:1',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
          delta: 'hello',
        ),
        AssistantDoneReceived(
          eventId: 'server:done:cli_1',
          sessionId: session,
          ts: base,
          replyTo: 'cli_1',
        ),
      ],
    );

    expect(projection.streaming, isNull);
    expect(projection.turn.status, TranscriptTurnStatus.idle);
  });

  test('compaction projects a system row', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        CompactionRecorded(
          eventId: 'server:compaction:1',
          sessionId: session,
          ts: base,
          summary: 'Short summary',
          tokensBefore: 123,
        ),
      ],
    );

    expect(projection.messages, [
      const CompactionMsg(
        id: 'server:compaction:1',
        summary: 'Short summary',
        tokensBefore: 123,
      ),
    ]);
  });

  test('duplicate server replay is idempotent by event id and message id', () {
    final event = confirmed('cli_1', 'hello');
    final sameMessageDifferentEventId = UserMessageConfirmed(
      eventId: 'server:user:cli_1:replay-2',
      sessionId: session,
      ts: base,
      clientMessageId: 'cli_1',
      text: 'hello again',
    );
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [event, event, sameMessageDifferentEventId],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
  });

  test('session-id filtering ignores foreign transcript events', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [
        confirmed('cli_1', 'hello'),
        confirmed('foreign', 'nope', s: 'sess-b'),
        submitted('foreign-pending', 'nope', s: 'sess-b'),
      ],
    );

    expect(projection.messages, [const UserMsg(id: 'cli_1', text: 'hello')]);
  });

  group('shared transcript projection fixtures', () {
    test(
      'optimistic send, authoritative echo, tool, done, and replay converge',
      () {
        final fixture = _fixtureNamed('optimistic-send-authoritative-replay');
        final projection = deriveTranscriptProjection(
          sessionId: fixture.sessionId,
          events: fixture.events,
        );

        expect(_appProjectionMessages(projection), fixture.expectedMessages);
        expect(projection.streaming, isNull);
        expect(projection.turn.status.name, fixture.expectedTurnStatus);
        expect(projection.turn.working, isFalse);
      },
    );

    test(
      'negative and convergence fixture pins filtering and idle recovery',
      () {
        final fixture = _fixtureNamed('convergence-negative-cases');
        final projection = deriveTranscriptProjection(
          sessionId: fixture.sessionId,
          events: fixture.events,
        );

        expect(_appProjectionMessages(projection), fixture.expectedMessages);
        expect(projection.streaming, isNull);
        expect(projection.turn.status.name, fixture.expectedTurnStatus);
        expect(projection.turn.working, isFalse);
        expect(
          projection.messages.whereType<UserMsg>().map((m) => m.id),
          isNot(contains('foreign_negative')),
        );
      },
    );
  });
}

final class _TranscriptFixture {
  const _TranscriptFixture({
    required this.name,
    required this.sessionId,
    required this.events,
    required this.expectedMessages,
    required this.expectedTurnStatus,
  });

  final String name;
  final String sessionId;
  final List<TranscriptEvent> events;
  final List<Map<String, Object?>> expectedMessages;
  final String expectedTurnStatus;
}

_TranscriptFixture _fixtureNamed(String name) {
  final file = File(
    '${Directory.current.parent.path}/.orchestration/contracts/transcript_projection_fixtures.json',
  );
  final root = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final fixtures = root['fixtures'] as List<Object?>;
  final raw = fixtures.cast<Map<String, Object?>>().singleWhere(
    (fixture) => fixture['name'] == name,
  );
  final projection = raw['projection'] as Map<String, Object?>;
  final turn = projection['turn'] as Map<String, Object?>;
  return _TranscriptFixture(
    name: raw['name'] as String,
    sessionId: raw['session_id'] as String,
    events: (raw['events'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(_eventFromJson)
        .toList(growable: false),
    expectedMessages: (projection['messages'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(_appExpectedMessage)
        .toList(growable: false),
    expectedTurnStatus: turn['status'] as String,
  );
}

TranscriptEvent _eventFromJson(Map<String, Object?> json) {
  final eventId = json['event_id'] as String;
  final sessionId = json['session_id'] as String;
  final ts = DateTime.utc(2026, 1, 1);
  return switch (json['kind'] as String) {
    'user_submitted' => UserMessageSubmitted(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      text: json['text'] as String,
    ),
    'user_confirmed' => UserMessageConfirmed(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      text: json['text'] as String,
    ),
    'user_failed' => UserMessageFailed(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
    ),
    'assistant_delta' => AssistantDeltaReceived(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      replyTo: json['replyTo'] as String,
      delta: json['delta'] as String,
    ),
    'assistant_committed' => AssistantMessageCommitted(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      messageId: json['messageId'] as String,
      replyTo: json['replyTo'] as String,
      text: json['text'] as String,
    ),
    'assistant_done' => AssistantDoneReceived(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      replyTo: json['replyTo'] as String,
    ),
    'tool_requested' => ToolRequested(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      toolCallId: json['toolCallId'] as String,
      tool: json['tool'] as String,
      args:
          (json['args'] as Map<String, Object?>?) ?? const <String, Object?>{},
    ),
    'tool_finished' => ToolFinished(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      toolCallId: json['toolCallId'] as String,
      result: json['result'],
      error: json['error'] as String?,
    ),
    'compaction_recorded' => CompactionRecorded(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      summary: json['summary'] as String,
      tokensBefore: (json['tokensBefore'] as num?)?.toInt(),
    ),
    final kind => throw UnsupportedError('Unknown fixture event kind: $kind'),
  };
}

List<Map<String, Object?>> _appProjectionMessages(
  TranscriptProjection projection,
) => projection.messages
    .map((message) {
      return switch (message) {
        UserMsg() => {
          'role': 'user',
          'id': message.id,
          'status': message.status.name,
          'text': message.text,
        },
        AssistantMsg() => {
          'role': 'assistant',
          'id': message.id,
          'text': message.text,
        },
        ToolEvent() => {
          'role': 'tool',
          'id': message.id,
          'toolCallId': message.toolCallId,
          'tool': message.tool,
          'status': message.status.name,
          'result': message.result,
        },
        CompactionMsg() => {
          'role': 'system',
          'id': message.id,
          'summary': message.summary,
          'tokensBefore': message.tokensBefore,
        },
      };
    })
    .toList(growable: false);

Map<String, Object?> _appExpectedMessage(Map<String, Object?> message) {
  return switch (message['role'] as String) {
    'user' => {
      'role': 'user',
      'id': message['id'],
      'status': message['status'],
      'text': message['text'],
    },
    'assistant' => {
      'role': 'assistant',
      'id': message['id'],
      'text': message['text'],
    },
    'tool' => {
      'role': 'tool',
      'id': message['id'],
      'toolCallId': message['toolCallId'],
      'tool': message['tool'],
      'status': message['status'],
      'result': message['result'],
    },
    'system' => {
      'role': 'system',
      'id': message['id'],
      'summary': message['summary'],
      'tokensBefore': message['tokensBefore'],
    },
    final role => throw UnsupportedError('Unknown fixture role: $role'),
  };
}
