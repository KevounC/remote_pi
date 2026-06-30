import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';

final class AgentSessionProjection {
  const AgentSessionProjection({
    required this.tabId,
    required this.projectId,
    required this.title,
    required this.lifecycle,
    required this.turn,
    required this.transcript,
    required this.controls,
    this.relayStatus = RelayStatus.disconnected,
    this.sessionId,
    this.sessionPath,
    this.pendingLocalSend = false,
  });

  factory AgentSessionProjection.empty({
    required String tabId,
    required String projectId,
    String title = 'New agent',
    String? sessionId,
    String? sessionPath,
  }) {
    return AgentSessionProjection(
      tabId: tabId,
      projectId: projectId,
      title: title,
      lifecycle: AgentProcessLifecycle.empty,
      turn: AgentTurnProjection.idle,
      transcript: _emptyTranscriptProjection,
      controls: const AgentControlsProjection(),
      sessionId: sessionId,
      sessionPath: sessionPath,
    );
  }

  final String tabId;
  final String projectId;
  final String title;
  final String? sessionId;
  final AgentProcessLifecycle lifecycle;
  final AgentTurnProjection turn;
  final CockpitTranscriptProjection transcript;
  final AgentControlsProjection controls;
  final RelayStatus relayStatus;
  final String? sessionPath;
  final bool pendingLocalSend;

  bool get isBusy => pendingLocalSend || turn.working;

  bool get isAlive => lifecycle.isAlive;
}

const _emptyTranscriptProjection = CockpitTranscriptProjection(
  entries: <ProjectedTranscriptMessage>[],
  turn: CockpitTranscriptTurnView(status: CockpitTranscriptTurnStatus.idle),
);

enum AgentProcessLifecycle { empty, booting, idle, running, crashed }

extension AgentProcessLifecycleState on AgentProcessLifecycle {
  bool get isAlive =>
      this == AgentProcessLifecycle.idle ||
      this == AgentProcessLifecycle.running;
}

final class AgentControlsProjection {
  const AgentControlsProjection({
    this.models = const <PiModel>[],
    this.commands = const <PiCommand>[],
    this.model,
    this.thinkingLevel = ThinkingLevel.off,
    this.contextUsage,
    this.preferredModelId,
    this.preferredThinking = ThinkingLevel.off,
  });

  final List<PiModel> models;
  final List<PiCommand> commands;
  final PiModel? model;
  final ThinkingLevel thinkingLevel;
  final ContextUsage? contextUsage;
  final String? preferredModelId;
  final ThinkingLevel preferredThinking;
}
