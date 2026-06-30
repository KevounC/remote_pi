import 'package:cockpit/app/cockpit/domain/entities/agent_session_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';

sealed class AgentSessionSignal {
  const AgentSessionSignal();
}

final class AgentTurnSignal extends AgentSessionSignal {
  const AgentTurnSignal({
    required this.event,
    this.now,
    this.error,
    this.clearPendingSend = false,
    this.closeTranscriptTurn = false,
    this.recordWorkedDuration = false,
    this.notifyOnCompletion = false,
    this.refreshStats = false,
  });

  final AgentTurnTransition event;
  final DateTime? now;
  final String? error;
  final bool clearPendingSend;
  final bool closeTranscriptTurn;
  final bool recordWorkedDuration;
  final bool notifyOnCompletion;
  final bool refreshStats;
}

final class AgentTranscriptSignal extends AgentSessionSignal {
  const AgentTranscriptSignal(this.event);

  final RpcEvent event;
}

final class AgentLifecycleSignal extends AgentSessionSignal {
  const AgentLifecycleSignal(this.lifecycle, {this.error});

  final AgentProcessLifecycle lifecycle;
  final String? error;
}
