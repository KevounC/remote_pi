import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/adapters/rpc_data_mapper.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Cockpit transcript projection', () {
    test('folds text, thinking, and tool events into immutable entries', () {
      final projection = deriveCockpitTranscript(<CockpitTranscriptEvent>[
        CockpitUserMessageConfirmed(
          eventId: 'e1',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          clientMessageId: 'u1',
          text: 'hello',
        ),
        CockpitThinkingDeltaReceived(
          eventId: 'e2',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          replyTo: 'u1',
          delta: 'think ',
        ),
        CockpitThinkingDeltaReceived(
          eventId: 'e3',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          replyTo: 'u1',
          delta: 'more',
        ),
        CockpitAssistantDeltaReceived(
          eventId: 'e4',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          replyTo: 'u1',
          delta: 'hel',
        ),
        CockpitAssistantDeltaReceived(
          eventId: 'e5',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          replyTo: 'u1',
          delta: 'lo',
        ),
        CockpitToolRequested(
          eventId: 'e6',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          toolCallId: 'tool-1',
          tool: 'read',
          args: const <String, Object?>{'path': 'README.md'},
        ),
        CockpitToolFinished(
          eventId: 'e7',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          toolCallId: 'tool-1',
          result: 'done',
        ),
      ]);

      expect(projection.entries, hasLength(4));
      expect(
        projection.entries[0],
        isA<ProjectedUserMessage>().having((m) => m.text, 'text', 'hello'),
      );
      expect(
        projection.entries[1],
        isA<ProjectedThinkingMessage>().having(
          (m) => m.text,
          'text',
          'think more',
        ),
      );
      expect(
        projection.entries[2],
        isA<ProjectedAssistantTextMessage>().having(
          (m) => m.text,
          'text',
          'hello',
        ),
      );
      expect(
        projection.entries[3],
        isA<ProjectedToolMessage>()
            .having((m) => m.status, 'status', ToolProjectionStatus.completed)
            .having((m) => m.resultText, 'resultText', 'done'),
      );
    });

    test('does not expose mutable tool projection state', () {
      final args = <String, dynamic>{'path': 'README.md'};
      final projection = deriveCockpitTranscript(<CockpitTranscriptEvent>[
        CockpitToolRequested(
          eventId: 'e1',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          toolCallId: 'tool-1',
          tool: 'read',
          args: args,
        ),
      ]);

      args['path'] = 'changed.md';
      final tool = projection.entries.single as ProjectedToolMessage;

      expect(tool.status, ToolProjectionStatus.running);
      expect(tool.args['path'], 'README.md');
      expect(() => tool.args['path'] = 'changed.md', throwsUnsupportedError);
    });

    test('event log dedupes hydration and filters by session', () {
      final log = CockpitTranscriptEventLog();
      final oldEvent = CockpitUserMessageConfirmed(
        eventId: 'old:u1',
        sessionId: 'old-session',
        ts: DateTime.utc(2026),
        clientMessageId: 'old-u1',
        text: 'old',
      );
      final activeEvent = CockpitUserMessageConfirmed(
        eventId: 'active:u1',
        sessionId: 'active-session',
        ts: DateTime.utc(2026),
        clientMessageId: 'active-u1',
        text: 'active',
      );

      log
        ..append(oldEvent)
        ..appendAll(<CockpitTranscriptEvent>[activeEvent, activeEvent]);

      expect(log.forSession('old-session'), <CockpitTranscriptEvent>[oldEvent]);
      expect(log.forSession('active-session'), <CockpitTranscriptEvent>[
        activeEvent,
      ]);
      expect(
        deriveCockpitTranscript(
          log.forSession('active-session'),
        ).entries.single,
        isA<ProjectedUserMessage>().having((m) => m.text, 'text', 'active'),
      );
    });
  });

  group('RpcDataMapper state', () {
    test('maps legacy isStreaming into a turn projection', () {
      final snapshot = const RpcDataMapper().state({
        'thinkingLevel': 'off',
        'isStreaming': true,
      });

      expect(snapshot.turn.status, AgentTurnStatus.streaming);
      expect(snapshot.turn.working, isTrue);
    });

    test('maps richer turn projection when present', () {
      final startedAt = DateTime.utc(2026, 6, 30, 12);
      final snapshot = const RpcDataMapper().state({
        'thinkingLevel': 'off',
        'isStreaming': false,
        'turn': {
          'status': 'error',
          'turnId': 'turn-1',
          'replyTo': 'message-1',
          'startedAt': startedAt.toIso8601String(),
          'error': 'provider failed',
        },
      });

      expect(snapshot.turn.status, AgentTurnStatus.error);
      expect(snapshot.turn.turnId, 'turn-1');
      expect(snapshot.turn.replyTo, 'message-1');
      expect(snapshot.turn.startedAt, startedAt);
      expect(snapshot.turn.error, 'provider failed');
      expect(snapshot.turn.working, isFalse);
    });
  });

  group('RpcDataMapper transcriptEvents', () {
    test('maps get_messages history to replayable transcript events', () {
      final events = const RpcDataMapper().transcriptEvents(
        _historyPayload,
        sessionId: 'selected-session',
      );

      expect(events, hasLength(5));
      expect(
        events[0],
        isA<CockpitUserMessageConfirmed>()
            .having((e) => e.sessionId, 'sessionId', 'selected-session')
            .having((e) => e.text, 'text', 'hello'),
      );
      expect(events[1], isA<CockpitThinkingDeltaReceived>());
      expect(events[2], isA<CockpitAssistantMessageCommitted>());
      expect(events[3], isA<CockpitToolRequested>());
      expect(
        events[4],
        isA<CockpitToolFinished>()
            .having((e) => e.toolCallId, 'toolCallId', 'tool-1')
            .having((e) => e.error, 'error', 'not found'),
      );

      final projection = deriveCockpitTranscript(events);
      expect(projection.entries, hasLength(4));
      expect(projection.entries[0], isA<ProjectedUserMessage>());
      expect(projection.entries[1], isA<ProjectedThinkingMessage>());
      expect(projection.entries[2], isA<ProjectedAssistantTextMessage>());
      expect(
        projection.entries[3],
        isA<ProjectedToolMessage>()
            .having((m) => m.status, 'status', ToolProjectionStatus.error)
            .having((m) => m.resultText, 'resultText', 'not found'),
      );
    });

    test('compatibility transcriptMessages uses the shared projection', () {
      final messages = const RpcDataMapper().transcriptMessages(
        _historyPayload,
      );

      expect(messages, hasLength(4));
      expect(messages[0], isA<ProjectedUserMessage>());
      expect(messages[1], isA<ProjectedThinkingMessage>());
      expect(messages[2], isA<ProjectedAssistantTextMessage>());
      expect(
        messages[3],
        isA<ProjectedToolMessage>()
            .having((m) => m.status, 'status', ToolProjectionStatus.error)
            .having((m) => m.resultText, 'resultText', 'not found'),
      );
    });
  });

  group('shared transcript projection fixtures', () {
    test('authoritative replay fixture converges to the shared projection', () {
      final fixture = _fixtureNamed('optimistic-send-authoritative-replay');
      final projection = deriveCockpitTranscript(
        _cockpitEventsForAuthoritativeReplay(fixture),
      );

      expect(_cockpitProjectionMessages(projection), fixture.expectedMessages);
      expect(projection.turn.status.name, fixture.expectedTurnStatus);
    });

    test('failed send and assistant done converge to non-working states', () {
      final failed = deriveCockpitTranscript(<CockpitTranscriptEvent>[
        CockpitUserMessageSubmitted(
          eventId: 'local:submit:failed',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          clientMessageId: 'failed_1',
          text: 'will fail',
        ),
        CockpitUserMessageFailed(
          eventId: 'local:failed:failed',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          clientMessageId: 'failed_1',
          code: 'cancelled',
          message: 'cancelled by user',
        ),
      ]);
      expect(failed.turn.status, CockpitTranscriptTurnStatus.error);

      final done = deriveCockpitTranscript(<CockpitTranscriptEvent>[
        CockpitAssistantDeltaReceived(
          eventId: 'server:delta:1',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          replyTo: 'failed_1',
          delta: 'partial',
        ),
        CockpitAssistantDoneReceived(
          eventId: 'server:done:failed_1',
          sessionId: 'local-session',
          ts: DateTime.utc(2026),
          replyTo: 'failed_1',
        ),
      ]);
      expect(done.turn.status, CockpitTranscriptTurnStatus.idle);
    });
  });
}

const _historyPayload = <String, Object?>{
  'session_id': 'opaque-session-id',
  'messages': <Object?>[
    <String, Object?>{'id': 'u1', 'role': 'user', 'content': 'hello'},
    <String, Object?>{
      'id': 'a1',
      'role': 'assistant',
      'content': <Object?>[
        <String, Object?>{'type': 'thinking', 'thinking': 'considering'},
        <String, Object?>{'type': 'text', 'text': 'hi'},
        <String, Object?>{
          'type': 'toolCall',
          'id': 'tool-1',
          'name': 'read',
          'arguments': <String, Object?>{'path': 'README.md'},
        },
      ],
    },
    <String, Object?>{
      'role': 'toolResult',
      'toolCallId': 'tool-1',
      'isError': true,
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': 'not found'},
      ],
    },
  ],
};

final class _CockpitFixture {
  const _CockpitFixture({
    required this.name,
    required this.sessionId,
    required this.rawEvents,
    required this.expectedMessages,
    required this.expectedTurnStatus,
  });

  final String name;
  final String sessionId;
  final List<Map<String, Object?>> rawEvents;
  final List<Map<String, Object?>> expectedMessages;
  final String expectedTurnStatus;
}

_CockpitFixture _fixtureNamed(String name) {
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
  return _CockpitFixture(
    name: raw['name'] as String,
    sessionId: raw['session_id'] as String,
    rawEvents: (raw['events'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .toList(growable: false),
    expectedMessages: (projection['messages'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(_cockpitExpectedMessage)
        .whereType<Map<String, Object?>>()
        .toList(growable: false),
    expectedTurnStatus: turn['status'] as String,
  );
}

List<CockpitTranscriptEvent> _cockpitEventsForAuthoritativeReplay(
  _CockpitFixture fixture,
) {
  final confirmedClientIds = fixture.rawEvents
      .where((event) => event['kind'] == 'user_confirmed')
      .map((event) => event['clientMessageId'])
      .toSet();
  final seenEventIds = <String>{};
  return fixture.rawEvents
      .where((event) => event['session_id'] == fixture.sessionId)
      .where((event) => seenEventIds.add(event['event_id'] as String))
      .where(
        (event) =>
            event['kind'] != 'user_submitted' ||
            !confirmedClientIds.contains(event['clientMessageId']),
      )
      .map(_cockpitEventFromJson)
      .whereType<CockpitTranscriptEvent>()
      .toList(growable: false);
}

CockpitTranscriptEvent? _cockpitEventFromJson(Map<String, Object?> json) {
  final eventId = json['event_id'] as String;
  final sessionId = json['session_id'] as String;
  final ts = DateTime.utc(2026, 1, 1);
  return switch (json['kind'] as String) {
    'user_submitted' => CockpitUserMessageSubmitted(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      text: json['text'] as String,
    ),
    'user_confirmed' => CockpitUserMessageConfirmed(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      text: json['text'] as String,
    ),
    'user_failed' => CockpitUserMessageFailed(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      clientMessageId: json['clientMessageId'] as String,
      code: json['code'] as String,
      message: json['message'] as String,
    ),
    'assistant_delta' => CockpitAssistantDeltaReceived(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      replyTo: json['replyTo'] as String,
      delta: json['delta'] as String,
    ),
    'assistant_committed' => CockpitAssistantMessageCommitted(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      messageId: json['messageId'] as String,
      replyTo: json['replyTo'] as String,
      text: json['text'] as String,
    ),
    'assistant_done' => CockpitAssistantDoneReceived(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      replyTo: json['replyTo'] as String,
    ),
    'tool_requested' => CockpitToolRequested(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      toolCallId: json['toolCallId'] as String,
      tool: json['tool'] as String,
      args:
          (json['args'] as Map<String, Object?>?) ?? const <String, Object?>{},
    ),
    'tool_finished' => CockpitToolFinished(
      eventId: eventId,
      sessionId: sessionId,
      ts: ts,
      toolCallId: json['toolCallId'] as String,
      result: json['result'],
      error: json['error'] as String?,
    ),
    // Cockpit step 5 clears buffers on compaction but does not yet expose a
    // projected system row; the app fixture test pins that generated-protocol
    // expectation until the desktop surface grows the row type.
    'compaction_recorded' => null,
    final kind => throw UnsupportedError('Unknown fixture event kind: $kind'),
  };
}

List<Map<String, Object?>> _cockpitProjectionMessages(
  CockpitTranscriptProjection projection,
) => projection.entries
    .map((message) {
      return switch (message) {
        ProjectedUserMessage() => {'role': 'user', 'text': message.text},
        ProjectedAssistantTextMessage() => {
          'role': 'assistant',
          'text': message.text,
        },
        ProjectedThinkingMessage() => {
          'role': 'thinking',
          'text': message.text,
        },
        ProjectedToolMessage() => {
          'role': 'tool',
          'toolCallId': message.callId,
          'tool': message.name,
          'status': message.status.name,
          'result': message.resultText,
        },
      };
    })
    .toList(growable: false);

Map<String, Object?>? _cockpitExpectedMessage(Map<String, Object?> message) {
  return switch (message['role'] as String) {
    'user' => {'role': 'user', 'text': message['text']},
    'assistant' => {'role': 'assistant', 'text': message['text']},
    'tool' => {
      'role': 'tool',
      'toolCallId': message['toolCallId'],
      'tool': message['tool'],
      'status': message['status'],
      'result': message['result'],
    },
    // No Cockpit system-row message type exists yet; app tests cover the shared
    // compaction expectation and this deferral is recorded in the story notes.
    'system' => null,
    final role => throw UnsupportedError('Unknown fixture role: $role'),
  };
}
