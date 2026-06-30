import 'package:app/data/sync/session_gate.dart';
import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/protocol/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const gate = SessionGate();
  const active = RemoteSessionRef(
    peerEpk: 'peer-1',
    roomId: 'main',
    sessionId: 'session-1',
  );

  test('accepts non-session control messages without an active session', () {
    final result = gate.accepts(Pong(inReplyTo: 'ping-1'), null);
    expect(result.accepted, isTrue);
  });

  test('rejects session-scoped messages when active session is unknown', () {
    final result = gate.accepts(
      AgentChunk(sessionId: 'session-1', inReplyTo: 'u1', delta: 'hello'),
      null,
    );
    expect(result.accepted, isFalse);
    expect(result.reason, 'active_session_unknown');
  });

  test('rejects missing session_id on session-scoped messages', () {
    final result = gate.accepts(
      AgentChunk(inReplyTo: 'u1', delta: 'hello'),
      active,
    );
    expect(result.accepted, isFalse);
    expect(result.reason, 'missing_session_id');
  });

  test('rejects mismatched session_id', () {
    final result = gate.accepts(
      SessionHistory(
        sessionId: 'session-2',
        inReplyTo: 'sync-1',
        sessionStartedAt: 1,
        events: const [],
        eos: true,
      ),
      active,
    );
    expect(result.accepted, isFalse);
    expect(result.reason, 'session_mismatch');
    expect(result.messageSessionId, 'session-2');
    expect(result.expectedSessionId, 'session-1');
  });

  test('accepts matching session_id', () {
    final result = gate.accepts(
      QueuedMessageState(sessionId: 'session-1', id: 'q1', text: 'next'),
      active,
    );
    expect(result.accepted, isTrue);
  });
}
