import 'dart:async';

import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_process_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_session_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_session_signal.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';

final class AgentSessionBootRequest {
  const AgentSessionBootRequest({
    required this.workingDirectory,
    this.environment,
    this.restoreSessionPath,
  });

  final String workingDirectory;
  final Map<String, String>? environment;
  final String? restoreSessionPath;
}

final class AgentPrompt {
  const AgentPrompt({required this.text, this.images = const <PromptImage>[]});

  final String text;
  final List<PromptImage> images;
}

/// Owns the local `pi --mode rpc` process effects for one agent tab.
///
/// `AgentSession` remains the UI-facing `ChangeNotifier`; this controller owns
/// the gateway instance, its event subscription, stdin commands, child kill, and
/// gateway disposal so restart/dispose paths converge through one lifecycle path.
final class AgentProcessController {
  AgentProcessController({required RpcGatewayFactory factory})
    : _factory = factory;

  final RpcGatewayFactory _factory;
  final StreamController<AgentSessionSignal> _signals =
      StreamController<AgentSessionSignal>.broadcast(sync: true);

  RpcProcessGateway? _gateway;
  StreamSubscription<RpcEvent>? _sub;
  bool _booting = false;
  bool _disposed = false;

  Stream<AgentSessionSignal> get signals => _signals.stream;

  bool get isRunning => _gateway?.isRunning ?? false;

  Future<void> boot(AgentSessionBootRequest request) async {
    if (_disposed || _booting || isRunning) return;
    _booting = true;
    _emit(const AgentLifecycleSignal(AgentProcessLifecycle.booting));

    final gateway = _factory.create();
    _gateway = gateway;
    final result = await gateway.spawn(
      workingDirectory: request.workingDirectory,
      environment: request.environment,
      sessionId: request.restoreSessionPath,
    );

    if (_disposed) {
      await _releaseGateway(gateway, kill: true);
      _booting = false;
      return;
    }

    result.fold(
      (_) {
        _sub = gateway.events.listen(_onEvent);
        _booting = false;
        _emit(const AgentLifecycleSignal(AgentProcessLifecycle.idle));
      },
      (error) {
        _booting = false;
        if (identical(_gateway, gateway)) _gateway = null;
        gateway.dispose();
        _emit(
          AgentLifecycleSignal(
            AgentProcessLifecycle.crashed,
            error: error.message,
          ),
        );
      },
    );
  }

  Future<Result<void, RpcError>?> send(AgentPrompt prompt) async {
    final gateway = _gateway;
    if (gateway == null) return null;
    return gateway.sendPrompt(prompt.text, images: prompt.images);
  }

  Future<Result<void, RpcError>?> stop() async {
    final result = await _gateway?.abort();
    result?.fold(
      (_) {
        _emit(
          const AgentTurnSignal(
            event: AgentTurnTransition.idle,
            clearPendingSend: true,
            closeTranscriptTurn: true,
          ),
        );
      },
      (error) {
        _emit(
          AgentTurnSignal(
            event: AgentTurnTransition.error,
            error: error.message,
            clearPendingSend: true,
          ),
        );
      },
    );
    return result;
  }

  Future<void> killForRestart() async {
    await _releaseCurrentGateway(kill: true);
    _emit(
      const AgentTurnSignal(
        event: AgentTurnTransition.stale,
        error: 'restarting with new configuration',
        clearPendingSend: true,
        closeTranscriptTurn: true,
      ),
    );
    _emit(const AgentLifecycleSignal(AgentProcessLifecycle.crashed));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _emit(
      const AgentTurnSignal(
        event: AgentTurnTransition.stale,
        error: 'disposed',
        clearPendingSend: true,
        closeTranscriptTurn: true,
      ),
    );
    _emit(const AgentLifecycleSignal(AgentProcessLifecycle.empty));
    await _releaseCurrentGateway(kill: true);
    await _signals.close();
  }

  Future<Result<List<PiModel>, RpcError>?> availableModels() async =>
      _gateway?.availableModels();

  Future<Result<List<PiCommand>, RpcError>?> commands() async =>
      _gateway?.commands();

  Future<Result<AgentSnapshot, RpcError>?> state() async => _gateway?.state();

  Future<Result<PiModel, RpcError>?> setModel(PiModel model) async =>
      _gateway?.setModel(model);

  Future<Result<void, RpcError>?> setThinkingLevel(ThinkingLevel level) async =>
      _gateway?.setThinkingLevel(level);

  Future<Result<void, RpcError>?> newSession() async => _gateway?.newSession();

  Future<Result<void, RpcError>?> compact() async => _gateway?.compact();

  Future<Result<void, RpcError>?> switchSession(String sessionPath) async =>
      _gateway?.switchSession(sessionPath);

  Future<Result<List<CockpitTranscriptEvent>, RpcError>?> getMessages({
    required String sessionId,
  }) async => _gateway?.getMessages(sessionId: sessionId);

  Future<Result<ContextUsage?, RpcError>?> sessionStats() async =>
      _gateway?.sessionStats();

  Future<Result<void, RpcError>?> respondUi(
    String id,
    Map<String, dynamic> response,
  ) async => _gateway?.respondUi(id, response);

  Future<Result<void, RpcError>?> sendControl(String verb) async =>
      _gateway?.sendControl(verb);

  void _onEvent(RpcEvent event) {
    switch (event) {
      case RpcAgentStart():
        _emit(
          AgentTurnSignal(
            event: AgentTurnTransition.started,
            now: DateTime.now(),
            clearPendingSend: true,
          ),
        );
      case RpcAgentEnd():
        _emit(
          const AgentTurnSignal(
            event: AgentTurnTransition.idle,
            closeTranscriptTurn: true,
            recordWorkedDuration: true,
            notifyOnCompletion: true,
            refreshStats: true,
          ),
        );
      case RpcThinkingDelta() || RpcTextDelta() || RpcToolStart():
        _emit(
          AgentTurnSignal(
            event: AgentTurnTransition.contentDelta,
            now: DateTime.now(),
          ),
        );
        _emit(AgentTranscriptSignal(event));
      case RpcStreamError(:final message):
        _emit(
          AgentTurnSignal(
            event: AgentTurnTransition.error,
            error: message,
            clearPendingSend: true,
          ),
        );
        _emit(AgentTranscriptSignal(event));
      case RpcProcessExit(:final code):
        _emit(const AgentLifecycleSignal(AgentProcessLifecycle.crashed));
        _emit(
          AgentTurnSignal(
            event: AgentTurnTransition.stale,
            error: 'process exited (code=$code)',
            clearPendingSend: true,
            closeTranscriptTurn: true,
          ),
        );
        _emit(AgentTranscriptSignal(event));
        unawaited(_releaseCurrentGateway(kill: false));
      default:
        _emit(AgentTranscriptSignal(event));
    }
  }

  Future<void> _releaseCurrentGateway({required bool kill}) async {
    final gateway = _gateway;
    _gateway = null;
    await _sub?.cancel();
    _sub = null;
    if (gateway != null) {
      await _releaseGateway(gateway, kill: kill);
    }
  }

  Future<void> _releaseGateway(
    RpcProcessGateway gateway, {
    required bool kill,
  }) async {
    if (kill) await gateway.kill();
    gateway.dispose();
  }

  void _emit(AgentSessionSignal signal) {
    if (_signals.isClosed) return;
    _signals.add(signal);
  }
}
