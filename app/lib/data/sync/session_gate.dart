import 'package:app/domain/entities/remote_session_ref.dart';
import 'package:app/protocol/protocol.dart';

final class SessionGateDecision {
  const SessionGateDecision._({
    required this.accepted,
    required this.reason,
    this.messageType,
    this.messageSessionId,
    this.expectedSessionId,
  });

  const SessionGateDecision.accepted()
    : this._(accepted: true, reason: 'accepted');

  const SessionGateDecision.rejected({
    required String reason,
    required String messageType,
    String? messageSessionId,
    String? expectedSessionId,
  }) : this._(
         accepted: false,
         reason: reason,
         messageType: messageType,
         messageSessionId: messageSessionId,
         expectedSessionId: expectedSessionId,
       );

  final bool accepted;
  final String reason;
  final String? messageType;
  final String? messageSessionId;
  final String? expectedSessionId;
}

final class SessionGate {
  const SessionGate();

  SessionGateDecision accepts(ServerMessage message, RemoteSessionRef? active) {
    final messageType = typeOfServerMessage(message);
    if (!isSessionScopedServerType(messageType)) {
      return const SessionGateDecision.accepted();
    }

    final expected = active?.sessionId;
    if (expected == null || expected.isEmpty) {
      return SessionGateDecision.rejected(
        reason: 'active_session_unknown',
        messageType: messageType,
        messageSessionId: sessionIdOfServerMessage(message),
      );
    }

    final actual = sessionIdOfServerMessage(message);
    if (actual == null || actual.isEmpty) {
      return SessionGateDecision.rejected(
        reason: 'missing_session_id',
        messageType: messageType,
        expectedSessionId: expected,
      );
    }

    if (actual != expected) {
      return SessionGateDecision.rejected(
        reason: 'session_mismatch',
        messageType: messageType,
        messageSessionId: actual,
        expectedSessionId: expected,
      );
    }

    return const SessionGateDecision.accepted();
  }
}
