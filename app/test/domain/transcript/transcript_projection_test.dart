import 'package:app/domain/session_state.dart';
import 'package:app/domain/transcript/transcript_event.dart';
import 'package:app/domain/transcript/transcript_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const session = 'sess-a';
  final base = DateTime.utc(2026, 1, 1);

  UserMessageSubmitted submitted(String id, String text, {String s = session}) =>
      UserMessageSubmitted(
        eventId: 'local:$id',
        sessionId: s,
        ts: base,
        clientMessageId: id,
        text: text,
      );

  UserMessageConfirmed confirmed(String id, String text, {String s = session}) =>
      UserMessageConfirmed(
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

  test('timeout marks pending local send failed while no confirmation exists', () {
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [submitted('cli_1', 'hello'), failed('cli_1', 'send timed out')],
    );

    expect(projection.messages, [
      const UserMsg(id: 'cli_1', text: 'hello', status: UserMsgStatus.failed),
    ]);
    expect(projection.turn.status, TranscriptTurnStatus.error);
  });

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

    expect(streaming.streaming, const StreamingMessage(inReplyTo: 'cli_1', buffer: 'hello'));
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
      const CompactionMsg(id: 'server:compaction:1', summary: 'Short summary', tokensBefore: 123),
    ]);
  });

  test('duplicate server replay is idempotent by event id and message id', () {
    final event = confirmed('cli_1', 'hello');
    final projection = deriveTranscriptProjection(
      sessionId: session,
      events: [event, event, confirmed('cli_1', 'hello again')],
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
}
