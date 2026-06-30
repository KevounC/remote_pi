import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_session_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_session_signal.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_entry.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_process_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:flutter/foundation.dart';

enum AgentStatus { empty, booting, idle, crashed }

/// Controlador de UM agente (uma aba do multiplexador). Dono de um
/// processo RPC próprio (criado pela fábrica), do transcript e dos
/// controles (modelo/effort/contexto/aprovação). `ChangeNotifier`: cada pane
/// escuta só a sua sessão, então um agente em streaming rebuilda só o seu pane.
class AgentSession extends PaneItem {
  AgentSession({
    required this.id,
    required this.projectId,
    required this.workingDirectory,
    required RpcGatewayFactory factory,
    String? title,
    this.autoStartRelay = false,
  }) : _process = AgentProcessController(factory: factory),
       _title = title ?? 'New agent' {
    _signalSub = _process.signals.listen(_onSignal);
  }

  @override
  final String id;
  @override
  final String projectId;

  /// Disparado quando o agente fecha um turno (`agent_end`). A VM usa pra
  /// notificar o workspace.
  VoidCallback? onTurnEnd;

  /// Disparado quando o usuário altera [preferredModelId] ou [preferredThinking].
  /// A VM usa pra agendar um save imediato — sem depender do fim de turno.
  VoidCallback? onPreferenceChanged;

  /// Foca o input do composer deste agente. Registrado pelo `AgentComposer`
  /// (quando montado) e disparado pelo atalho ⌘L/Ctrl+L.
  VoidCallback? requestComposerFocus;

  /// Pasta (subpasta do projeto) onde o `pi --mode rpc` roda.
  @override
  final String workingDirectory;

  /// Conectar ao relay ao iniciar (injetado em `REMOTE_PI_DIRECT_CONFIG`).
  bool autoStartRelay;

  /// Estado atual da conexão do relay (atualizado por `remote-pi:relay-state`).
  RelayStatus relayStatus = RelayStatus.disconnected;

  /// ID do modelo que o usuário escolheu para este agente (ex: `'claude-sonnet-4-6'`).
  /// `null` = nunca foi alterado → pi decide o default.
  /// Persistido no layout; aplicado automaticamente após cada boot via [_loadControls].
  String? preferredModelId;

  /// Nível de effort preferido. Persistido e reaplicado após cada boot.
  ThinkingLevel preferredThinking = ThinkingLevel.off;

  final AgentProcessController _process;
  StreamSubscription<AgentSessionSignal>? _signalSub;

  /// Caminho do arquivo de sessão do pi (`~/.pi/agent/sessions/<cwd>/*.jsonl`)
  /// que pertence a este agente. Capturado pela VM no 1º fim de turno e usado
  /// pra reanexar a conversa ao restaurar o workspace.
  String? sessionPath;

  /// Sessões que já existiam na pasta **antes** deste agente bootar — a VM usa
  /// pra descobrir, por diferença, qual arquivo o pi criou pra ele.
  Set<String>? sessionBaseline;

  String _title;
  AgentStatus _status = AgentStatus.empty;

  /// `true` entre o `sendPrompt` e o `RpcAgentStart`: a mensagem foi enviada
  /// mas o agente ainda não confirmou que iniciou o turno. Bloqueia novo envio
  /// sem acender o indicador de "trabalhando" (que só aparece com AgentStart).
  bool _pendingSend = false;

  /// Textos de mensagens enviadas **localmente** que já entraram otimisticamente
  /// no transcript e estão aguardando o eco `message_start:user` do pi. Quando o
  /// eco chega e bate com uma entrada daqui, ignoramos (senão duplica a bolha).
  /// Mensagens do app/mesh não passam por aqui → viram bolha normalmente.
  final List<String> _awaitingUserEcho = <String>[];

  AgentTurnProjection _turn = AgentTurnProjection.idle;
  CockpitTranscriptProjection _transcriptProjection =
      _emptyTranscriptProjection;
  final List<AgentEntry> _entries = <AgentEntry>[];
  final List<CockpitTranscriptEvent> _transcriptEvents =
      <CockpitTranscriptEvent>[];
  var _transcriptEventSeq = 0;

  List<PiModel> _models = const <PiModel>[];
  List<PiCommand> _commands = const <PiCommand>[];
  PiModel? _model;
  ThinkingLevel _thinking = ThinkingLevel.off;
  ContextUsage? _ctx;

  /// `true` quando o agente fechou um turno e o usuário ainda não olhou — move
  /// a evidência na aba e conta pro badge do workspace.
  bool _unseenFinish = false;
  @override
  bool get unseenFinish => _unseenFinish;

  void markUnseen() {
    if (_unseenFinish) return;
    _unseenFinish = true;
    notifyListeners();
  }

  @override
  void clearUnseen() {
    if (!_unseenFinish) return;
    _unseenFinish = false;
    notifyListeners();
  }

  /// Pedidos interativos da extensão (`extension_ui_request`) ainda abertos,
  /// por `id` — pra marcar o card como resolvido ao responder.
  final Map<String, UiRequestEntry> _openUiRequests =
      <String, UiRequestEntry>{};

  // ---- getters (UI) ---------------------------------------------------------
  @override
  String get title => _title;

  AgentSessionProjection get projection => AgentSessionProjection(
    tabId: id,
    projectId: projectId,
    title: _title,
    lifecycle: _lifecycle,
    turn: _turn,
    transcript: _transcriptProjection,
    controls: AgentControlsProjection(
      models: _models,
      commands: _commands,
      model: _model,
      thinkingLevel: _thinking,
      contextUsage: _ctx,
      preferredModelId: preferredModelId,
      preferredThinking: preferredThinking,
    ),
    relayStatus: relayStatus,
    sessionId: _transcriptSessionId,
    sessionPath: sessionPath,
    pendingLocalSend: _pendingSend,
  );

  AgentStatus get status => projection.lifecycle.toLegacyStatus();

  AgentTurnProjection get turn => projection.turn;

  /// Início do turno em andamento (`null` se ocioso).
  DateTime? get turnStartedAt => projection.turn.startedAt;
  bool get isStreaming => projection.turn.status == AgentTurnStatus.streaming;
  bool get isBusy => projection.isBusy;
  bool get isAlive => projection.isAlive;
  List<AgentEntry> get entries => List<AgentEntry>.unmodifiable(_entries);
  List<PiModel> get models => projection.controls.models;
  List<PiCommand> get commands => projection.controls.commands;
  PiModel? get model => projection.controls.model;
  ThinkingLevel get thinking => projection.controls.thinkingLevel;
  ContextUsage? get contextUsage => projection.controls.contextUsage;

  AgentProcessLifecycle get _lifecycle => switch (_status) {
    AgentStatus.empty => AgentProcessLifecycle.empty,
    AgentStatus.booting => AgentProcessLifecycle.booting,
    AgentStatus.idle => AgentProcessLifecycle.idle,
    AgentStatus.crashed => AgentProcessLifecycle.crashed,
  };

  // ---- lifecycle ------------------------------------------------------------

  /// Sobe o `pi --mode rpc` na [workingDirectory] e começa a ouvir o stream.
  ///
  /// [environment] é fundido com o ambiente do processo pai — use para injetar
  /// `REMOTE_PI_DIRECT_CONFIG` sem perder PATH/HOME. Se `null`, herda tudo.
  ///
  /// [restoreSessionPath] (opcional) é o caminho completo do `.jsonl` a
  /// restaurar. Quando presente, passa `--session <id>` ao pi para que ele
  /// inicie já naquela sessão — sem `switch_session` posterior, evitando a
  /// re-avaliação dupla do módulo da extensão.
  Future<void> boot({
    Map<String, String>? environment,
    String? restoreSessionPath,
  }) async {
    if (_status == AgentStatus.booting || isAlive) return;
    debugPrint('[agent-boot] boot() id=$id cwd=$workingDirectory');
    _status = AgentStatus.booting;
    _turn = AgentTurnProjection.idle;
    _pendingSend = false;
    _entries.clear();
    _awaitingUserEcho.clear();
    _transcriptEvents.clear();
    _transcriptProjection = _emptyTranscriptProjection;
    notifyListeners();

    await _process.boot(
      AgentSessionBootRequest(
        workingDirectory: workingDirectory,
        environment: environment,
        restoreSessionPath: restoreSessionPath,
      ),
    );
    if (!_process.isRunning) return;
    _addInfo('agent ready in $workingDirectory');
    unawaited(_loadControls());
    unawaited(_syncRelayStatus());
    if (restoreSessionPath != null) {
      unawaited(_populateTranscript(restoreSessionPath));
    }
    notifyListeners();
  }

  Future<void> send(
    String message, {
    List<PromptImage> images = const <PromptImage>[],
  }) async {
    final text = message.trim();
    if ((text.isEmpty && images.isEmpty) || !isAlive || isBusy) {
      return;
    }
    // Balão do usuário: texto + miniaturas das imagens (decodifica o base64
    // uma vez pra exibir). Status permanece idle até RpcAgentStart confirmar
    // o início do turno — comandos não-bloqueantes (compact etc.) não devem
    // acender o indicador de "trabalhando".
    _appendTranscriptEvent(
      CockpitUserMessageSubmitted(
        eventId: _nextTranscriptEventId(),
        sessionId: _transcriptSessionId,
        ts: DateTime.now(),
        clientMessageId: _nextTranscriptEventId(),
        text: text,
        images: [for (final image in images) base64Decode(image.data)],
      ),
    );
    // Marca pra deduplicar o eco `message_start:user` que o pi vai emitir.
    _awaitingUserEcho.add(text);
    _pendingSend = true;
    notifyListeners();
    final result = await _process.send(AgentPrompt(text: text, images: images));
    if (result == null) {
      _pendingSend = false;
      notifyListeners();
      return;
    }
    result.fold((_) {}, (error) {
      _addInfo('failed to send: ${error.message}', isError: true);
      _pendingSend = false;
      notifyListeners();
    });
  }

  /// Interrompe o turno atual (não mata o processo).
  Future<void> stop() async {
    final result = await _process.stop();
    result?.fold((_) {}, (error) {
      _addInfo('failed to stop: ${error.message}', isError: true);
      notifyListeners();
    });
  }

  /// `/new` — começa uma sessão nova: zera a conversa. O `sessionPath` é
  /// resetado pra a VM recapturar o novo arquivo de sessão no próximo turno.
  Future<void> startNewSession() async {
    if (!_process.isRunning || isBusy) return;
    final result = await _process.newSession();
    if (result == null) return;
    result.fold(
      (_) {
        _pendingSend = false;
        _reduceTurn(AgentTurnTransition.idle);
        _entries.clear();
        _transcriptEvents.clear();
        _transcriptProjection = _emptyTranscriptProjection;
        _ctx = null;
        sessionPath = null;
        _addInfo('new session');
        notifyListeners();
        // sessionPath mudou → pede à VM para salvar o layout agora (sem esperar
        // o próximo fim de turno, que pode nunca vir antes do app fechar).
        onPreferenceChanged?.call();
      },
      (error) {
        _addInfo('failed to create session: ${error.message}', isError: true);
        notifyListeners();
      },
    );
  }

  /// `/compact` — compacta o contexto da sessão.
  Future<void> compact() async {
    if (!_process.isRunning || isBusy) return;
    final result = await _process.compact();
    if (result == null) return;
    result.fold(
      (_) => _addInfo('context compacted'),
      (error) => _addInfo('failed to compact: ${error.message}', isError: true),
    );
    notifyListeners();
    unawaited(_refreshStats()); // o contexto mudou
  }

  Future<void> changeModel(PiModel model) async {
    if (!_process.isRunning || isBusy || model == _model) return;
    final result = await _process.setModel(model);
    if (result == null) return;
    result.fold(
      (applied) {
        _model = applied;
        preferredModelId = applied.id; // persiste a escolha do usuário
        onPreferenceChanged?.call();
      },
      (error) {
        _addInfo('failed to switch model: ${error.message}', isError: true);
      },
    );
    notifyListeners();
    unawaited(_refreshStats());
  }

  Future<void> changeThinking(ThinkingLevel level) async {
    if (!_process.isRunning || isBusy || level == _thinking) return;
    final result = await _process.setThinkingLevel(level);
    if (result == null) return;
    result.fold(
      (_) {
        _thinking = level;
        preferredThinking = level; // persiste a escolha do usuário
        onPreferenceChanged?.call();
      },
      (error) {
        _addInfo('failed to change effort: ${error.message}', isError: true);
      },
    );
    notifyListeners();
  }

  /// Troca de sessão interativamente (picker de histórico) e recarrega o
  /// transcript. Usa `switch_session` para mudar a sessão no processo pi vivo.
  Future<void> loadHistory(String sessionPath) async {
    if (!_process.isRunning || isBusy) return;

    final switched = await _process.switchSession(sessionPath);
    if (switched == null) return;
    final ok = switched.fold((_) => true, (error) {
      _addInfo('failed to switch session: ${error.message}', isError: true);
      notifyListeners();
      return false;
    });
    if (!ok) return;

    await _populateTranscript(sessionPath);
  }

  /// Busca as mensagens da sessão atual do pi e substitui o transcript exibido.
  /// Chamado após boot com `--session <id>` (sem `switch_session`) e após
  /// [loadHistory] (que já fez o `switch_session`).
  Future<void> _populateTranscript(String sessionPath) async {
    if (!_process.isRunning) return;

    final result = await _process.getMessages(sessionId: sessionPath);
    if (result == null) return;
    result.fold(
      (events) {
        _entries.clear();
        this.sessionPath = sessionPath;
        _awaitingUserEcho.clear();
        _transcriptEvents
          ..clear()
          ..addAll(events);
        _replaceProjectedTranscript();
        _status = AgentStatus.idle;
        _pendingSend = false;
        _reduceTurn(AgentTurnTransition.idle);
        notifyListeners();
        onPreferenceChanged?.call();
      },
      (error) {
        _addInfo('failed to load history: ${error.message}', isError: true);
        notifyListeners();
      },
    );
  }

  void rename(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _title) return;
    _title = trimmed;
    notifyListeners();
  }

  /// Mata o processo e reseta o status para `crashed`, mas mantém a sessão
  /// viva na UI. Use antes de chamar `boot()` novamente com nova config.
  Future<void> killForRestart() async {
    final wasAlive = _status == AgentStatus.booting || isAlive;
    await _process.killForRestart();
    if (wasAlive) {
      _addInfo('restarting with new configuration...');
      notifyListeners();
    }
  }

  /// Mata o processo limpo e libera o gateway. Chamado ao fechar a aba.
  @override
  Future<void> dispose() async {
    await _process.dispose();
    await _signalSub?.cancel();
    _signalSub = null;
    super.dispose();
  }

  // ---- controles (request/response) -----------------------------------------

  /// Liga/desliga/alterna o relay sem envolver o LLM. Não aparece no transcript.
  /// [verb]: `relay:on` | `relay:off` | `relay:toggle` | `relay:status`.
  Future<void> sendRelayControl(String verb) async {
    await _process.sendControl(verb);
  }

  /// Solicita o estado atual do relay ao pi (resposta chega como RpcRelayState).
  Future<void> _syncRelayStatus() async {
    await _process.sendControl('relay:status');
  }

  Future<void> _loadControls() async {
    if (!_process.isRunning) return;
    final modelsResult = await _process.availableModels();
    modelsResult?.fold((list) => _models = list, (_) {});
    final commandsResult = await _process.commands();
    commandsResult?.fold((list) => _commands = list, (_) {});
    final stateResult = await _process.state();
    stateResult?.fold((snapshot) {
      _model = snapshot.model;
      _thinking = snapshot.thinkingLevel;
      // `get_state` is a boot-time snapshot; do not let a stale idle snapshot
      // erase a live turn that has already arrived on the event stream.
      if (!_turn.working || snapshot.turn.working) {
        _turn = snapshot.turn;
      }
    }, (_) {});
    notifyListeners();
    unawaited(_refreshStats());
    // Reaplicar preferências do usuário (persistidas do boot anterior).
    unawaited(_applyPreferred());
  }

  /// Envia `set_model` / `set_thinking_level` silenciosamente se as preferências
  /// diferem do estado que o pi subiu. Erros são descartados (o pi pode não ter
  /// o modelo; a UI continua com o default dele nesse caso).
  Future<void> _applyPreferred() async {
    if (!_process.isRunning) return;
    final pid = preferredModelId;
    if (pid != null) {
      final target = _models.where((m) => m.id == pid).firstOrNull;
      if (target != null && target != _model) {
        final r = await _process.setModel(target);
        r?.fold((applied) => _model = applied, (_) {});
        notifyListeners();
      }
    }
    if (preferredThinking != _thinking) {
      final r = await _process.setThinkingLevel(preferredThinking);
      r?.fold((_) => _thinking = preferredThinking, (_) {});
      notifyListeners();
    }
  }

  Future<void> _refreshStats() async {
    if (!_process.isRunning || !isAlive) return;
    final result = await _process.sessionStats();
    result?.fold((usage) {
      if (usage != null) _ctx = usage;
    }, (_) {});
    notifyListeners();
  }

  // ---- signal projection ----------------------------------------------------

  void _onSignal(AgentSessionSignal signal) {
    switch (signal) {
      case AgentTurnSignal():
        _onTurnSignal(signal);
      case AgentTranscriptSignal(:final event):
        _onTranscriptSignal(event);
      case AgentLifecycleSignal(:final lifecycle, :final error):
        _status = lifecycle.toLegacyStatus();
        if (lifecycle == AgentProcessLifecycle.crashed && error != null) {
          _addInfo('failed to start: $error', isError: true);
        }
    }
    notifyListeners();
  }

  void _onTurnSignal(AgentTurnSignal signal) {
    final wasWorking = _turn.working;
    final startedAt = _turn.startedAt;
    if (signal.clearPendingSend) _pendingSend = false;
    _reduceTurn(signal.event, now: signal.now, error: signal.error);
    if (signal.closeTranscriptTurn) _closeTranscriptTurn();
    if (signal.recordWorkedDuration && wasWorking && startedAt != null) {
      _add(WorkedEntry(DateTime.now().difference(startedAt)));
    }
    if (signal.refreshStats) unawaited(_refreshStats());
    if (signal.notifyOnCompletion && wasWorking) onTurnEnd?.call();
  }

  void _onTranscriptSignal(RpcEvent event) {
    switch (event) {
      case RpcAgentStart() || RpcAgentEnd():
        return;
      case RpcTurnStart():
        _closeTranscriptTurn();
      case RpcTurnEnd():
        _closeTranscriptTurn();
      case RpcThinkingDelta(:final delta):
        _appendTranscriptEvent(
          CockpitThinkingDeltaReceived(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            replyTo: id,
            delta: delta,
          ),
        );
      case RpcTextDelta(:final delta):
        _appendTranscriptEvent(
          CockpitAssistantDeltaReceived(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            replyTo: id,
            delta: delta,
          ),
        );
      case RpcTextEnd(:final content):
        _appendTranscriptEvent(
          CockpitAssistantMessageCommitted(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            messageId: _nextTranscriptEventId(),
            replyTo: id,
            text: content,
          ),
        );
      case RpcUserMessage(:final text):
        // Eco da nossa própria mensagem local → já está no transcript, ignora.
        // Caso contrário, é mensagem vinda do app/mesh → mostra a bolha.
        if (_awaitingUserEcho.remove(text)) return;
        _appendTranscriptEvent(
          CockpitUserMessageConfirmed(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            clientMessageId: _nextTranscriptEventId(),
            text: text,
          ),
        );
      case RpcToolStart(:final toolCallId, :final toolName, :final args):
        _appendTranscriptEvent(
          CockpitToolRequested(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            toolCallId: toolCallId,
            tool: toolName,
            args: args,
          ),
        );
      case RpcToolEnd(:final toolCallId, :final isError, :final resultText):
        _appendTranscriptEvent(
          CockpitToolFinished(
            eventId: _nextTranscriptEventId(),
            sessionId: _transcriptSessionId,
            ts: DateTime.now(),
            toolCallId: toolCallId,
            result: resultText,
            error: isError ? resultText : null,
          ),
        );
      case RpcCommandResponse(:final command, :final success, :final error):
        if (!success) {
          _addInfo('command "$command" failed: ${error ?? "?"}', isError: true);
        }
      case RpcStreamError(:final message):
        _addInfo('agent error: $message', isError: true, dedup: true);
      case RpcAutoRetry(
        :final attempt,
        :final maxAttempts,
        :final delayMs,
        :final message,
      ):
        _addInfo('retrying ($attempt/$maxAttempts in ${delayMs}ms) — $message');
      case RpcDiagnostic(:final text):
        _addInfo('stderr: $text');
      case RpcProcessExit(:final code):
        _addInfo('process exited (code=$code)', isError: code != 0);
      case RpcNotice(:final message, :final level):
        _add(NoticeEntry(message, level.index));
      case RpcUiRequest(
        :final id,
        :final method,
        :final title,
        :final message,
        :final placeholder,
        :final defaultValue,
        :final options,
      ):
        _openUiRequests[id] = _add(
          UiRequestEntry(
            id: id,
            method: method,
            title: title,
            message: message,
            placeholder: placeholder,
            defaultValue: defaultValue,
            options: options,
          ),
        );
      case RpcRelayState(:final status):
        relayStatus = status;
      case RpcNameAssigned(:final assigned, :final changed):
        if (changed) {
          rename(assigned);
          onPreferenceChanged?.call(); // persiste no layout imediatamente
        }
      case RpcUnknown():
        return;
    }
  }

  /// Responde a um pedido interativo da extensão (card do transcript) e marca o
  /// card como resolvido. [response] é `{value:…}`/`{confirmed:…}`/`{cancelled:
  /// true}`; [label] é o texto que o card mostra depois ("você escolheu …").
  void respondUi(String id, Map<String, dynamic> response, String label) {
    final entry = _openUiRequests.remove(id);
    if (entry != null) {
      entry.resolved = true;
      entry.answerLabel = label;
    }
    unawaited(_process.respondUi(id, response));
    notifyListeners();
  }

  // ---- helpers --------------------------------------------------------------

  void _reduceTurn(
    AgentTurnTransition transition, {
    DateTime? now,
    String? error,
  }) {
    _turn = reduceAgentTurnProjection(
      _turn,
      transition,
      now: now,
      error: error,
    );
  }

  T _add<T extends AgentEntry>(T entry) {
    _entries.add(entry);
    return entry;
  }

  String get _transcriptSessionId => sessionPath ?? id;

  String _nextTranscriptEventId() => '$id:${_transcriptEventSeq++}';

  void _appendTranscriptEvent(CockpitTranscriptEvent event) {
    _transcriptEvents.add(event);
    _replaceProjectedTranscript();
  }

  void _closeTranscriptTurn() {
    if (_transcriptEvents.isEmpty) return;
    if (_transcriptProjection.turn.status == CockpitTranscriptTurnStatus.idle) {
      return;
    }
    _appendTranscriptEvent(
      CockpitAssistantDoneReceived(
        eventId: _nextTranscriptEventId(),
        sessionId: _transcriptSessionId,
        ts: DateTime.now(),
        replyTo: id,
      ),
    );
  }

  void _replaceProjectedTranscript() {
    final firstProjectedIndex = _entries.indexWhere(
      _isProjectedTranscriptEntry,
    );
    _entries.removeWhere(_isProjectedTranscriptEntry);
    _transcriptProjection = deriveCockpitTranscript(_transcriptEvents);
    final projected = _transcriptProjection.entries;
    final newEntries = projected.map(_toAgentEntry).toList(growable: false);
    final insertionIndex = firstProjectedIndex < 0
        ? _entries.length
        : firstProjectedIndex > _entries.length
        ? _entries.length
        : firstProjectedIndex;
    _entries.insertAll(insertionIndex, newEntries);
  }

  bool _isProjectedTranscriptEntry(AgentEntry entry) {
    return entry is UserEntry ||
        entry is AssistantTextEntry ||
        entry is ThinkingEntry ||
        entry is ToolEntry;
  }

  AgentEntry _toAgentEntry(ProjectedTranscriptMessage message) {
    switch (message) {
      case ProjectedUserMessage(:final text, :final images):
        return UserEntry(text, images: images);
      case ProjectedAssistantTextMessage(:final text):
        return AssistantTextEntry(text);
      case ProjectedThinkingMessage(:final text):
        return ThinkingEntry(text);
      case ProjectedToolMessage(
        :final callId,
        :final name,
        :final args,
        :final status,
        :final resultText,
      ):
        final tool = ToolEntry(toolCallId: callId, toolName: name, args: args);
        tool.done = status != ToolProjectionStatus.running;
        tool.isError = status == ToolProjectionStatus.error;
        tool.resultText = resultText;
        return tool;
    }
  }

  void _addInfo(String text, {bool isError = false, bool dedup = false}) {
    if (dedup) {
      final last = _entries.isNotEmpty ? _entries.last : null;
      if (last is InfoEntry && last.text == text) return;
    }
    _add(InfoEntry(text, isError: isError));
  }
}

const _emptyTranscriptProjection = CockpitTranscriptProjection(
  entries: <ProjectedTranscriptMessage>[],
  turn: CockpitTranscriptTurnView(status: CockpitTranscriptTurnStatus.idle),
);

extension on AgentProcessLifecycle {
  AgentStatus toLegacyStatus() => switch (this) {
    AgentProcessLifecycle.empty => AgentStatus.empty,
    AgentProcessLifecycle.booting => AgentStatus.booting,
    AgentProcessLifecycle.idle => AgentStatus.idle,
    AgentProcessLifecycle.running => AgentStatus.idle,
    AgentProcessLifecycle.crashed => AgentStatus.crashed,
  };
}
