import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';

/// Recorte do estado do agente vivo — de `get_state`. O Cockpit usa para
/// preencher a seleção atual dos seletores (modelo + effort) ao bootar e para
/// hidratar a projeção de turno.
class AgentSnapshot {
  const AgentSnapshot({
    required this.model,
    required this.thinkingLevel,
    required this.turn,
  });

  final PiModel? model;
  final ThinkingLevel thinkingLevel;
  final AgentTurnProjection turn;
}
