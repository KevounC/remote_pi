import 'package:cockpit/app/cockpit/domain/entities/agent_session_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentSessionProjection', () {
    test('empty snapshot is not alive or busy', () {
      final projection = AgentSessionProjection.empty(
        tabId: 'tab-1',
        projectId: 'project-1',
      );

      expect(projection.lifecycle, AgentProcessLifecycle.empty);
      expect(projection.turn, AgentTurnProjection.idle);
      expect(projection.transcript.entries, isEmpty);
      expect(projection.relayStatus, RelayStatus.disconnected);
      expect(projection.isAlive, isFalse);
      expect(projection.isBusy, isFalse);
    });

    test('booting snapshot is not alive and does not imply work', () {
      final projection = _projection(lifecycle: AgentProcessLifecycle.booting);

      expect(projection.isAlive, isFalse);
      expect(projection.isBusy, isFalse);
    });

    test('idle snapshot is alive and not busy', () {
      final projection = _projection(lifecycle: AgentProcessLifecycle.idle);

      expect(projection.isAlive, isTrue);
      expect(projection.isBusy, isFalse);
    });

    test('streaming snapshot reuses the turn and transcript projections', () {
      final transcript = deriveCockpitTranscript([
        CockpitAssistantDeltaReceived(
          eventId: 'event-1',
          sessionId: 'session-1',
          ts: DateTime.utc(2026, 6, 30),
          replyTo: 'message-1',
          delta: 'hello',
        ),
      ]);
      final projection = _projection(
        lifecycle: AgentProcessLifecycle.running,
        turn: const AgentTurnProjection(status: AgentTurnStatus.streaming),
        transcript: transcript,
      );

      expect(projection.isAlive, isTrue);
      expect(projection.isBusy, isTrue);
      expect(projection.turn.status, AgentTurnStatus.streaming);
      expect(
        projection.transcript.turn.status,
        CockpitTranscriptTurnStatus.streaming,
      );
      expect(
        projection.transcript.entries.single,
        isA<ProjectedAssistantTextMessage>(),
      );
    });

    test('pending local send is busy even before the agent starts a turn', () {
      final projection = _projection(
        lifecycle: AgentProcessLifecycle.idle,
        pendingLocalSend: true,
      );

      expect(projection.turn.working, isFalse);
      expect(projection.isAlive, isTrue);
      expect(projection.isBusy, isTrue);
    });

    test(
      'crashed snapshot is not alive or busy after stale turn convergence',
      () {
        final projection = _projection(
          lifecycle: AgentProcessLifecycle.crashed,
          turn: const AgentTurnProjection(
            status: AgentTurnStatus.stale,
            error: 'process exited',
          ),
        );

        expect(projection.isAlive, isFalse);
        expect(projection.turn.working, isFalse);
        expect(projection.isBusy, isFalse);
      },
    );
  });
}

AgentSessionProjection _projection({
  required AgentProcessLifecycle lifecycle,
  AgentTurnProjection turn = AgentTurnProjection.idle,
  CockpitTranscriptProjection transcript = const CockpitTranscriptProjection(
    entries: <ProjectedTranscriptMessage>[],
    turn: CockpitTranscriptTurnView(status: CockpitTranscriptTurnStatus.idle),
  ),
  bool pendingLocalSend = false,
}) {
  return AgentSessionProjection(
    tabId: 'tab-1',
    projectId: 'project-1',
    title: 'Agent',
    lifecycle: lifecycle,
    turn: turn,
    transcript: transcript,
    controls: const AgentControlsProjection(),
    sessionId: 'session-1',
    sessionPath: '/sessions/session-1.jsonl',
    pendingLocalSend: pendingLocalSend,
  );
}
