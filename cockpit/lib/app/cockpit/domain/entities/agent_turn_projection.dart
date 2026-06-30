/// UI-facing projection of an agent turn.
///
/// Process lifecycle (`empty`/`booting`/`idle`/`crashed`) is owned separately by
/// `AgentStatus`; this projection answers whether the current conversational
/// turn is working, streaming output, terminal with an error, or stale after the
/// owning process/session was replaced.
enum AgentTurnStatus { idle, working, streaming, error, stale }

final class AgentTurnProjection {
  const AgentTurnProjection({
    required this.status,
    this.turnId,
    this.replyTo,
    this.startedAt,
    this.error,
  });

  static const idle = AgentTurnProjection(status: AgentTurnStatus.idle);

  final AgentTurnStatus status;
  final String? turnId;
  final String? replyTo;
  final DateTime? startedAt;
  final String? error;

  bool get working =>
      status == AgentTurnStatus.working || status == AgentTurnStatus.streaming;

  bool get canStop => working;
}

enum AgentTurnTransition { started, contentDelta, idle, error, stale }

/// Single reducer for turn-status convergence. Every terminal transition clears
/// [startedAt], so UI affordances cannot stay stuck in a working state after
/// success, failure, abort, process exit, history load, or restart.
AgentTurnProjection reduceAgentTurnProjection(
  AgentTurnProjection current,
  AgentTurnTransition transition, {
  DateTime? now,
  String? turnId,
  String? replyTo,
  String? error,
}) {
  switch (transition) {
    case AgentTurnTransition.started:
      return AgentTurnProjection(
        status: AgentTurnStatus.working,
        turnId: turnId ?? current.turnId,
        replyTo: replyTo ?? current.replyTo,
        startedAt: current.startedAt ?? now,
      );
    case AgentTurnTransition.contentDelta:
      return AgentTurnProjection(
        status: AgentTurnStatus.streaming,
        turnId: turnId ?? current.turnId,
        replyTo: replyTo ?? current.replyTo,
        startedAt: current.startedAt ?? now,
      );
    case AgentTurnTransition.idle:
      return AgentTurnProjection.idle;
    case AgentTurnTransition.error:
      return AgentTurnProjection(
        status: AgentTurnStatus.error,
        turnId: turnId ?? current.turnId,
        replyTo: replyTo ?? current.replyTo,
        error: error,
      );
    case AgentTurnTransition.stale:
      return AgentTurnProjection(
        status: AgentTurnStatus.stale,
        turnId: turnId ?? current.turnId,
        replyTo: replyTo ?? current.replyTo,
        error: error,
      );
  }
}
