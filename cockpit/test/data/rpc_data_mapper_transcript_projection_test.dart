import 'package:cockpit/app/cockpit/data/adapters/rpc_data_mapper.dart';
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
  });

  group('RpcDataMapper transcriptMessages', () {
    test('uses the shared projection for get_messages history', () {
      final messages = const RpcDataMapper().transcriptMessages({
        'session_id': 'opaque-session-id',
        'messages': [
          {'id': 'u1', 'role': 'user', 'content': 'hello'},
          {
            'id': 'a1',
            'role': 'assistant',
            'content': [
              {'type': 'thinking', 'thinking': 'considering'},
              {'type': 'text', 'text': 'hi'},
              {
                'type': 'toolCall',
                'id': 'tool-1',
                'name': 'read',
                'arguments': {'path': 'README.md'},
              },
            ],
          },
          {
            'role': 'toolResult',
            'toolCallId': 'tool-1',
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'not found'},
            ],
          },
        ],
      });

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
}
