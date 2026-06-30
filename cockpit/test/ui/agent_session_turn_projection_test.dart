import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_process_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_session_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_entry.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('projects start to streaming to end and clears elapsed state', () async {
    final (session, gateway) = await _bootSession();

    gateway.emit(const RpcAgentStart());
    expect(session.turn.status, AgentTurnStatus.working);
    expect(session.turn.working, isTrue);
    expect(session.isStreaming, isFalse);
    expect(session.isBusy, isTrue);
    expect(session.turnStartedAt, isNotNull);

    gateway.emit(const RpcTextDelta('hello'));
    expect(session.turn.status, AgentTurnStatus.streaming);
    expect(session.isStreaming, isTrue);

    gateway.emit(const RpcAgentEnd());
    expect(session.status, AgentStatus.idle);
    expect(session.turn.status, AgentTurnStatus.idle);
    expect(session.turn.working, isFalse);
    expect(session.isBusy, isFalse);
    expect(session.turnStartedAt, isNull);

    await session.dispose();
  });

  test('stream errors converge to not working and clear startedAt', () async {
    final (session, gateway) = await _bootSession();

    gateway
      ..emit(const RpcAgentStart())
      ..emit(const RpcTextDelta('partial'))
      ..emit(const RpcStreamError('provider failed'));

    expect(session.status, AgentStatus.idle);
    expect(session.turn.status, AgentTurnStatus.error);
    expect(session.turn.error, 'provider failed');
    expect(session.turn.working, isFalse);
    expect(session.isBusy, isFalse);
    expect(session.turnStartedAt, isNull);

    await session.dispose();
  });

  test('stop abort acknowledgement converges to idle', () async {
    final (session, gateway) = await _bootSession();

    gateway
      ..emit(const RpcAgentStart())
      ..emit(const RpcTextDelta('partial'));
    expect(session.turn.canStop, isTrue);

    await session.stop();

    expect(gateway.abortCount, 1);
    expect(session.turn.status, AgentTurnStatus.idle);
    expect(session.turn.working, isFalse);
    expect(session.isBusy, isFalse);
    expect(session.turnStartedAt, isNull);

    await session.dispose();
  });

  test('process exit marks the turn stale and not working', () async {
    final (session, gateway) = await _bootSession();

    gateway
      ..emit(const RpcAgentStart())
      ..emit(const RpcTextDelta('partial'))
      ..emit(const RpcProcessExit(1));

    expect(session.status, AgentStatus.crashed);
    expect(session.turn.status, AgentTurnStatus.stale);
    expect(session.turn.error, 'process exited (code=1)');
    expect(session.turn.working, isFalse);
    expect(session.isBusy, isFalse);
    expect(session.turnStartedAt, isNull);

    await session.dispose();
  });

  test('restored history load clears a legacy streaming snapshot', () async {
    final messages = Completer<List<CockpitTranscriptEvent>>();
    final (session, gateway) = await _bootSession(
      stateTurn: const AgentTurnProjection(status: AgentTurnStatus.streaming),
      restoreSessionPath: '/sessions/restored.jsonl',
      messages: messages,
      settle: false,
    );

    await pumpEventQueue();
    expect(gateway.stateCount, 1);
    expect(session.turn.status, AgentTurnStatus.streaming);
    expect(session.isBusy, isTrue);

    messages.complete(const <CockpitTranscriptEvent>[]);
    await pumpEventQueue();

    expect(session.sessionPath, '/sessions/restored.jsonl');
    expect(session.turn.status, AgentTurnStatus.idle);
    expect(session.turn.working, isFalse);
    expect(session.isBusy, isFalse);
    expect(session.turnStartedAt, isNull);

    await session.dispose();
  });

  test(
    'get_messages replay replaces transcript through projection events',
    () async {
      final messages = Completer<List<CockpitTranscriptEvent>>();
      final (session, gateway) = await _bootSession(
        restoreSessionPath: '/sessions/restored.jsonl',
        messages: messages,
        settle: false,
      );

      final replayed = <CockpitTranscriptEvent>[
        CockpitUserMessageConfirmed(
          eventId: 'history:u1',
          sessionId: '/sessions/restored.jsonl',
          ts: _ts,
          clientMessageId: 'u1',
          text: 'hello history',
        ),
        CockpitAssistantMessageCommitted(
          eventId: 'history:a1',
          sessionId: '/sessions/restored.jsonl',
          ts: _ts,
          messageId: 'a1',
          replyTo: 'u1',
          text: 'hello back',
        ),
      ];
      messages.complete(replayed);
      await pumpEventQueue();

      expect(gateway.getMessagesSessionIds, <String>[
        '/sessions/restored.jsonl',
      ]);
      expect(_transcriptEntries(session), hasLength(2));
      expect(
        _transcriptEntries(session)[0],
        isA<UserEntry>().having((entry) => entry.text, 'text', 'hello history'),
      );
      expect(
        _transcriptEntries(session)[1],
        isA<AssistantTextEntry>().having(
          (entry) => entry.text,
          'text',
          'hello back',
        ),
      );

      await session.dispose();
    },
  );

  test(
    'live streaming text deltas accumulate through transcript projection',
    () async {
      final (session, gateway) = await _bootSession();

      gateway
        ..emit(const RpcTextDelta('hel'))
        ..emit(const RpcTextDelta('lo'));

      final textEntries = _transcriptEntries(
        session,
      ).whereType<AssistantTextEntry>();
      expect(textEntries, hasLength(1));
      expect(textEntries.single.text, 'hello');
      expect(
        session.projection.transcript.entries.single,
        isA<ProjectedAssistantTextMessage>(),
      );

      await session.dispose();
    },
  );

  test(
    'live tool start and result collapse into one projected tool row',
    () async {
      final (session, gateway) = await _bootSession();

      gateway
        ..emit(
          const RpcToolStart(
            toolCallId: 'tool-1',
            toolName: 'read_file',
            args: <String, dynamic>{'path': 'README.md'},
          ),
        )
        ..emit(
          const RpcToolEnd(
            toolCallId: 'tool-1',
            toolName: 'read_file',
            isError: false,
            resultText: 'ok',
          ),
        );

      final tools = _transcriptEntries(session).whereType<ToolEntry>();
      expect(tools, hasLength(1));
      expect(tools.single.toolCallId, 'tool-1');
      expect(tools.single.done, isTrue);
      expect(tools.single.isError, isFalse);
      expect(tools.single.resultText, 'ok');

      await session.dispose();
    },
  );

  test('local optimistic user send suppresses matching rpc echo', () async {
    final (session, gateway) = await _bootSession();

    await session.send('hello');
    gateway.emit(const RpcUserMessage('hello'));

    final users = _transcriptEntries(session).whereType<UserEntry>();
    expect(users, hasLength(1));
    expect(users.single.text, 'hello');

    await session.dispose();
  });

  test(
    'history reload clears prior open projected text and tool rows',
    () async {
      final messages = Completer<List<CockpitTranscriptEvent>>();
      final (session, gateway) = await _bootSession(messages: messages);

      gateway
        ..emit(const RpcTextDelta('old partial'))
        ..emit(
          const RpcToolStart(
            toolCallId: 'old-tool',
            toolName: 'old_tool',
            args: <String, dynamic>{},
          ),
        )
        ..emit(const RpcAgentEnd());
      expect(
        _transcriptEntries(session).whereType<AssistantTextEntry>(),
        hasLength(1),
      );
      expect(_transcriptEntries(session).whereType<ToolEntry>(), hasLength(1));

      final load = session.loadHistory('/sessions/new.jsonl');
      messages.complete(<CockpitTranscriptEvent>[
        CockpitUserMessageConfirmed(
          eventId: 'new:u1',
          sessionId: '/sessions/new.jsonl',
          ts: _ts,
          clientMessageId: 'new-u1',
          text: 'new history',
        ),
      ]);
      await load;

      expect(gateway.getMessagesSessionIds, <String>['/sessions/new.jsonl']);
      expect(
        _transcriptEntries(session).whereType<AssistantTextEntry>(),
        isEmpty,
      );
      expect(_transcriptEntries(session).whereType<ToolEntry>(), isEmpty);
      expect(
        _transcriptEntries(session).single,
        isA<UserEntry>().having((entry) => entry.text, 'text', 'new history'),
      );

      await session.dispose();
    },
  );

  test('new session clears prior terminal turn error', () async {
    final (session, gateway) = await _bootSession();

    gateway
      ..emit(const RpcAgentStart())
      ..emit(const RpcStreamError('cancelled'));
    session.sessionPath = '/sessions/old.jsonl';

    await session.startNewSession();

    expect(gateway.newSessionCount, 1);
    expect(session.sessionPath, isNull);
    expect(session.turn.status, AgentTurnStatus.idle);
    expect(session.turn.working, isFalse);
    expect(session.turnStartedAt, isNull);

    await session.dispose();
  });

  test('restart kill marks the turn stale and not working', () async {
    final (session, gateway) = await _bootSession();

    gateway
      ..emit(const RpcAgentStart())
      ..emit(const RpcTextDelta('partial'));

    await session.killForRestart();

    expect(gateway.killCount, 1);
    expect(session.status, AgentStatus.crashed);
    expect(session.turn.status, AgentTurnStatus.stale);
    expect(session.turn.working, isFalse);
    expect(session.isBusy, isFalse);
    expect(session.turnStartedAt, isNull);
  });

  test(
    'projection-backed compatibility getters preserve busy and alive semantics',
    () async {
      final (session, gateway) = await _bootSession();

      expect(session.status, AgentStatus.idle);
      expect(session.projection.lifecycle, AgentProcessLifecycle.idle);
      expect(session.isAlive, session.projection.isAlive);
      expect(session.isBusy, session.projection.isBusy);

      await session.send('hello');
      expect(session.projection.pendingLocalSend, isTrue);
      expect(session.projection.turn.working, isFalse);
      expect(session.isAlive, isTrue);
      expect(session.isBusy, isTrue);
      expect(session.isBusy, session.projection.isBusy);

      gateway.emit(const RpcAgentStart());
      expect(session.projection.pendingLocalSend, isFalse);
      expect(session.turn.status, AgentTurnStatus.working);
      expect(session.isAlive, isTrue);
      expect(session.isBusy, isTrue);
      expect(session.isBusy, session.projection.isBusy);

      gateway.emit(const RpcProcessExit(1));
      expect(session.status, AgentStatus.crashed);
      expect(session.projection.lifecycle, AgentProcessLifecycle.crashed);
      expect(session.isAlive, isFalse);
      expect(session.isBusy, isFalse);
      expect(session.isAlive, session.projection.isAlive);
      expect(session.isBusy, session.projection.isBusy);

      await session.dispose();
    },
  );
}

final _ts = DateTime.utc(2026, 6, 30);

List<AgentEntry> _transcriptEntries(AgentSession session) => session.entries
    .where(
      (entry) =>
          entry is UserEntry ||
          entry is AssistantTextEntry ||
          entry is ThinkingEntry ||
          entry is ToolEntry,
    )
    .toList(growable: false);

Future<(AgentSession, _RpcGateway)> _bootSession({
  AgentTurnProjection stateTurn = AgentTurnProjection.idle,
  String? restoreSessionPath,
  Completer<List<CockpitTranscriptEvent>>? messages,
  bool settle = true,
}) async {
  final factory = _RpcFactory(
    _RpcGateway(stateTurn: stateTurn, messages: messages),
  );
  final session = AgentSession(
    id: 'a1',
    projectId: 'p1',
    workingDirectory: '/workspace',
    factory: factory,
    title: 'agent',
  );
  await session.boot(restoreSessionPath: restoreSessionPath);
  if (settle) await pumpEventQueue();
  return (session, factory.gateway);
}

final class _RpcFactory implements RpcGatewayFactory {
  _RpcFactory(this.gateway);

  final _RpcGateway gateway;

  @override
  RpcProcessGateway create() => gateway;
}

final class _RpcGateway implements RpcProcessGateway {
  _RpcGateway({required this.stateTurn, this.messages});

  final _events = StreamController<RpcEvent>.broadcast(sync: true);
  final AgentTurnProjection stateTurn;
  final Completer<List<CockpitTranscriptEvent>>? messages;
  var stateCount = 0;
  var abortCount = 0;
  var newSessionCount = 0;
  var killCount = 0;
  final getMessagesSessionIds = <String>[];
  var _running = false;
  String? _cwd;

  void emit(RpcEvent event) => _events.add(event);

  @override
  Stream<RpcEvent> get events => _events.stream;

  @override
  bool get isRunning => _running;

  @override
  String? get workingDirectory => _cwd;

  @override
  Future<Result<void, RpcError>> spawn({
    required String workingDirectory,
    Map<String, String>? environment,
    String? sessionId,
  }) async {
    _running = true;
    _cwd = workingDirectory;
    return const Success(null);
  }

  @override
  Future<Result<void, RpcError>> abort() async {
    abortCount++;
    return const Success(null);
  }

  @override
  Future<Result<List<PiModel>, RpcError>> availableModels() async =>
      const Success([]);

  @override
  Future<Result<void, RpcError>> compact() async => const Success(null);

  @override
  Future<Result<List<PiCommand>, RpcError>> commands() async =>
      const Success([]);

  @override
  void dispose() => unawaited(_events.close());

  @override
  Future<Result<List<CockpitTranscriptEvent>, RpcError>> getMessages({
    required String sessionId,
  }) async {
    getMessagesSessionIds.add(sessionId);
    return Success(await (messages?.future ?? Future.value(const [])));
  }

  @override
  Future<Result<ContextUsage?, RpcError>> sessionStats() async =>
      const Success(null);

  @override
  Future<Result<AgentSnapshot, RpcError>> state() async {
    stateCount++;
    return Success(
      AgentSnapshot(
        model: null,
        thinkingLevel: ThinkingLevel.off,
        turn: stateTurn,
      ),
    );
  }

  @override
  Future<void> kill() async {
    killCount++;
    _running = false;
  }

  @override
  Future<Result<void, RpcError>> newSession() async {
    newSessionCount++;
    return const Success(null);
  }

  @override
  Future<Result<void, RpcError>> respondUi(
    String id,
    Map<String, dynamic> response,
  ) async => const Success(null);

  @override
  Future<Result<void, RpcError>> sendControl(String verb) async =>
      const Success(null);

  @override
  Future<Result<void, RpcError>> sendPrompt(
    String message, {
    bool steerIfBusy = false,
    List<PromptImage> images = const <PromptImage>[],
  }) async => const Success(null);

  @override
  Future<Result<PiModel, RpcError>> setModel(PiModel model) async =>
      Success(model);

  @override
  Future<Result<void, RpcError>> setThinkingLevel(ThinkingLevel level) async =>
      const Success(null);

  @override
  Future<Result<void, RpcError>> switchSession(String sessionPath) async =>
      const Success(null);
}
