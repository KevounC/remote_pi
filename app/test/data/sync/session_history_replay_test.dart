import 'package:app/data/sync/session_history_replay.dart';
import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sessionId = 'sess-replay';
  const ts = 1716234601000;

  SessionHistory history({
    required String inReplyTo,
    required List<SessionHistoryEvent> events,
  }) => SessionHistory(
    sessionId: sessionId,
    inReplyTo: inReplyTo,
    sessionStartedAt: 1700000000000,
    events: events,
    eos: true,
  );

  group('sessionHistoryToTranscriptEvents', () {
    test('replays user input with image as authoritative confirmation', () {
      final events = sessionHistoryToTranscriptEvents(
        history: history(
          inReplyTo: 'sync-a',
          events: const [
            UserInputEvt(
              ts: ts,
              id: 'client-1',
              text: 'describe this',
              image: WireImage(data: 'base64-image', mime: 'image/png'),
            ),
          ],
        ),
        sessionId: sessionId,
      );

      expect(events, hasLength(1));
      final event = events.single;
      expect(event, isA<UserMessageConfirmed>());
      final confirmed = event as UserMessageConfirmed;
      expect(
        confirmed.eventId,
        serverReplayEventId(sessionId, 'user_input', 'client-1', ts),
      );
      expect(confirmed.sessionId, sessionId);
      expect(confirmed.ts, DateTime.fromMillisecondsSinceEpoch(ts));
      expect(confirmed.clientMessageId, 'client-1');
      expect(confirmed.text, 'describe this');
      expect(
        confirmed.image,
        const MessageImage(data: 'base64-image', mime: 'image/png'),
      );
    });

    test('replays assistant messages with deterministic message ids', () {
      final events = sessionHistoryToTranscriptEvents(
        history: history(
          inReplyTo: 'sync-a',
          events: const [
            AgentMessageEvt(ts: ts, inReplyTo: 'client-1', text: 'done'),
          ],
        ),
        sessionId: sessionId,
      );

      final assistant = events.single as AssistantMessageCommitted;
      expect(
        assistant.eventId,
        serverReplayEventId(sessionId, 'agent_message', 'client-1', ts),
      );
      expect(
        assistant.messageId,
        serverReplayMessageId(sessionId, 'agent_message', 'client-1', ts),
      );
      expect(assistant.replyTo, 'client-1');
      expect(assistant.text, 'done');
    });

    test('replays tool request and result facts', () {
      final events = sessionHistoryToTranscriptEvents(
        history: history(
          inReplyTo: 'sync-a',
          events: const [
            ToolRequestEvt(
              ts: ts,
              toolCallId: 'tool-1',
              tool: 'Bash',
              args: {'cmd': 'pwd'},
            ),
            ToolResultEvt(
              ts: ts + 1,
              toolCallId: 'tool-1',
              result: {'stdout': '/tmp'},
              error: null,
            ),
            ToolResultEvt(
              ts: ts + 2,
              toolCallId: 'tool-2',
              result: null,
              error: 'denied',
            ),
          ],
        ),
        sessionId: sessionId,
      );

      final requested = events[0] as ToolRequested;
      expect(
        requested.eventId,
        serverReplayEventId(sessionId, 'tool_request', 'tool-1', ts),
      );
      expect(requested.toolCallId, 'tool-1');
      expect(requested.tool, 'Bash');
      expect(requested.args, {'cmd': 'pwd'});

      final finished = events[1] as ToolFinished;
      expect(
        finished.eventId,
        serverReplayEventId(sessionId, 'tool_result', 'tool-1', ts + 1),
      );
      expect(finished.toolCallId, 'tool-1');
      expect(finished.result, {'stdout': '/tmp'});
      expect(finished.error, isNull);

      final failed = events[2] as ToolFinished;
      expect(failed.toolCallId, 'tool-2');
      expect(failed.result, isNull);
      expect(failed.error, 'denied');
    });

    test('replays compaction with token count', () {
      final events = sessionHistoryToTranscriptEvents(
        history: history(
          inReplyTo: 'sync-a',
          events: const [
            CompactionEvt(
              ts: ts,
              summary: 'compacted summary',
              tokensBefore: 12345,
            ),
          ],
        ),
        sessionId: sessionId,
      );

      final compaction = events.single as CompactionRecorded;
      expect(
        compaction.eventId,
        serverReplayEventId(sessionId, 'compaction', 'compaction', ts),
      );
      expect(compaction.summary, 'compacted summary');
      expect(compaction.tokensBefore, 12345);
    });

    test('ignores request id when deriving deterministic replay ids', () {
      const replayEvents = [
        UserInputEvt(ts: ts, id: 'client-1', text: 'hello'),
        AgentMessageEvt(ts: ts + 1, inReplyTo: 'client-1', text: 'hi'),
        ToolRequestEvt(
          ts: ts + 2,
          toolCallId: 'tool-1',
          tool: 'Bash',
          args: {'cmd': 'pwd'},
        ),
        ToolResultEvt(ts: ts + 3, toolCallId: 'tool-1', result: 'ok'),
        CompactionEvt(ts: ts + 4, summary: 'summary'),
      ];

      final first = sessionHistoryToTranscriptEvents(
        history: history(inReplyTo: 'sync-request-1', events: replayEvents),
        sessionId: sessionId,
      );
      final second = sessionHistoryToTranscriptEvents(
        history: history(inReplyTo: 'sync-request-2', events: replayEvents),
        sessionId: sessionId,
      );

      expect(
        first.map((event) => event.eventId),
        second.map((event) => event.eventId),
      );
    });

    test('duplicate server facts produce stable duplicate event ids', () {
      final events = sessionHistoryToTranscriptEvents(
        history: history(
          inReplyTo: 'sync-a',
          events: const [
            UserInputEvt(ts: ts, id: 'client-1', text: 'hello'),
            UserInputEvt(ts: ts, id: 'client-1', text: 'hello'),
          ],
        ),
        sessionId: sessionId,
      );

      expect(events, hasLength(2));
      expect(events[0].eventId, events[1].eventId);
      expect(
        events[0].eventId,
        serverReplayEventId(sessionId, 'user_input', 'client-1', ts),
      );
    });

    test('fails fast for unsupported future history event types', () {
      expect(
        () => SessionHistoryEvent.fromJson({
          'type': 'future_history_type',
          'ts': ts,
        }),
        throwsA(isA<UnsupportedTypeException>()),
      );
    });

    test('fails fast when canonical session id is missing', () {
      expect(
        () => sessionHistoryToTranscriptEvents(
          history: history(
            inReplyTo: 'sync-a',
            events: const [UserInputEvt(ts: ts, id: 'client-1', text: 'hello')],
          ),
          sessionId: '',
        ),
        throwsArgumentError,
      );
    });
  });
}
