import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_process_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_turn_projection.dart';
import 'package:cockpit/app/cockpit/domain/entities/context_usage.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/pi_model.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/prompt_image.dart';
import 'package:cockpit/app/cockpit/domain/entities/rpc_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/transcript_message.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads, exposes, and saves a workspace document round-trip', () async {
    final project = await _project();
    final layout = <String, dynamic>{
      'v': 1,
      'focused': 'pane1',
      'tree': <String, dynamic>{
        'k': 'leaf',
        'id': 'pane1',
        'tabs': <String>['a7', 't8', 'v9', 'a10'],
        'active': 'a7',
      },
      'sessions': <String, dynamic>{
        'a7': <String, dynamic>{
          'type': 'agent',
          'sub': 'lib',
          'title': 'Agent',
          'sessionPath': '/sessions/a7.jsonl',
          'auto_start_relay': true,
          'preferred_model': 'model-a',
          'preferred_thinking': 'high',
        },
        't8': <String, dynamic>{
          'type': 'terminal',
          'sub': 'tools',
          'title': 'Tools',
        },
        'v9': <String, dynamic>{
          'type': 'viewer',
          'path': '${project.path}/README.md',
        },
        'a10': <String, dynamic>{'type': 'empty', 'title': 'New'},
      },
    };
    final store = _LayoutStore({'p1': layout});
    final vm = _viewModel(projects: [project], store: store);

    await vm.init();
    await Future<void>.delayed(Duration.zero);

    expect(vm.focusedPaneId('p1'), 'pane1');
    expect(vm.tree('p1'), isNotNull);
    expect(vm.session('a7'), isA<AgentSession>());
    expect(vm.session('t8')?.title, 'Tools');
    expect(vm.session('v9')?.title, 'README.md');
    expect(vm.session('a10'), isA<AgentSession>());

    vm.toggleRail();
    await Future<void>.delayed(const Duration(milliseconds: 650));

    expect(store.saved['p1'], layout);
    vm.dispose();
  });

  test('clamps invalid persisted focus and exposes focus changes', () async {
    final project = await _project();
    final store = _LayoutStore({
      'p1': <String, dynamic>{
        'v': 1,
        'focused': 'missing-pane',
        'tree': <String, dynamic>{
          'k': 'split',
          'id': 'sp1',
          'dir': 'vertical',
          'frac': 0.5,
          'a': <String, dynamic>{
            'k': 'leaf',
            'id': 'paneA',
            'tabs': <String>['a1'],
            'active': 'a1',
          },
          'b': <String, dynamic>{
            'k': 'leaf',
            'id': 'paneB',
            'tabs': <String>['a2'],
            'active': 'a2',
          },
        },
        'sessions': <String, dynamic>{
          'a1': <String, dynamic>{'type': 'empty', 'title': 'New'},
          'a2': <String, dynamic>{'type': 'empty', 'title': 'New'},
        },
      },
    });
    final vm = _viewModel(projects: [project], store: store);

    await vm.init();

    expect(vm.focusedPaneId('p1'), 'paneA');
    vm.focus('paneB');
    expect(vm.focusedPaneId('p1'), 'paneB');
    await Future<void>.delayed(Duration.zero);
    vm.dispose();
  });

  test(
    'drops unrestorable viewer tabs and inserts live empty placeholders',
    () async {
      final project = await _project();
      final store = _LayoutStore({
        'p1': <String, dynamic>{
          'v': 1,
          'focused': 'pane1',
          'tree': <String, dynamic>{
            'k': 'leaf',
            'id': 'pane1',
            'tabs': <String>['v1'],
            'active': 'v1',
          },
          'sessions': <String, dynamic>{
            'v1': <String, dynamic>{
              'type': 'viewer',
              'path': '${project.path}/missing.md',
            },
          },
        },
      });
      final vm = _viewModel(projects: [project], store: store);

      await vm.init();

      final leaf = vm.tree('p1')! as LeafPane;
      final tabs = leaf.tabs;
      expect(tabs, hasLength(1));
      expect(tabs.single, isNot('v1'));
      expect(vm.session(tabs.single), isA<AgentSession>());
      expect(vm.focusedPaneId('p1'), 'pane1');

      vm.toggleTree();
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(
        (store.saved['p1']!['sessions'] as Map).containsKey('v1'),
        isFalse,
      );
      expect(
        (store.saved['p1']!['sessions'] as Map).containsKey(tabs.single),
        isTrue,
      );
      await Future<void>.delayed(Duration.zero);
      vm.dispose();
    },
  );
}

Future<Project> _project() async {
  final dir = await Directory.systemTemp.createTemp('cockpit-vm-doc-test-');
  return Project(
    id: 'p1',
    name: 'Workspace',
    path: dir.path,
    colorValue: 0xFF000000,
    createdAt: DateTime(2026),
  );
}

CockpitViewModel _viewModel({
  required List<Project> projects,
  required _LayoutStore store,
}) {
  return CockpitViewModel(
    _ProjectRepo(projects),
    _RpcFactory(),
    _Folders(),
    _History(),
    _Notifier(),
    _FileSystem(),
    _TerminalFactory(),
    _FileReader(),
    store,
    _GitReader(),
    _Searcher(),
    _Launcher(),
    _Worktrees(),
    _Mutator(),
    LspServerPool(_LspFactory()),
  );
}

final class _ProjectRepo implements ProjectRepository {
  _ProjectRepo(this._projects);
  final List<Project> _projects;
  String? lastSelected;

  @override
  Future<List<Project>> all() async => _projects;

  @override
  Future<String?> loadLastSelected() async => lastSelected;

  @override
  Future<void> remove(String id) async {}

  @override
  Future<void> save(Project project) async {}

  @override
  Future<void> saveLastSelected(String? id) async => lastSelected = id;
}

final class _LayoutStore implements WorkspaceLayoutStore {
  _LayoutStore(this._initial);
  final Map<String, Map<String, dynamic>?> _initial;
  final Map<String, Map<String, dynamic>> saved = {};

  @override
  Future<Map<String, dynamic>?> load(String projectId) async =>
      _initial[projectId];

  @override
  Future<void> remove(String projectId) async => saved.remove(projectId);

  @override
  Future<void> save(String projectId, Map<String, dynamic> document) async {
    saved[projectId] = document;
  }
}

final class _FileReader implements FileReader {
  @override
  Future<FileView> read(String path) async {
    if (path.endsWith('missing.md')) return const FileViewUnsupported();
    return FileViewText('content for $path', language: 'text');
  }

  @override
  Stream<void> watch(String path) => const Stream<void>.empty();

  @override
  Future<bool> write(String path, String content) async => true;
}

final class _RpcFactory implements RpcGatewayFactory {
  @override
  RpcProcessGateway create() => _RpcGateway();
}

final class _RpcGateway implements RpcProcessGateway {
  final _events = StreamController<RpcEvent>.broadcast();
  bool _running = false;
  String? _cwd;

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
    return const Success<void, RpcError>(null);
  }

  @override
  Future<Result<void, RpcError>> abort() async => const Success(null);

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
  Future<Result<List<TranscriptMessage>, RpcError>> getMessages() async =>
      const Success([]);

  @override
  Future<Result<AgentSnapshot, RpcError>> state() async => const Success(
    AgentSnapshot(
      model: null,
      thinkingLevel: ThinkingLevel.off,
      turn: AgentTurnProjection.idle,
    ),
  );

  @override
  Future<Result<ContextUsage?, RpcError>> sessionStats() async =>
      const Success(null);

  @override
  Future<void> kill() async {
    _running = false;
  }

  @override
  Future<Result<void, RpcError>> newSession() async => const Success(null);

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
  Future<Result<void, RpcError>> setThinkingLevel(ThinkingLevel level) async =>
      const Success(null);

  @override
  Future<Result<PiModel, RpcError>> setModel(PiModel model) async =>
      Success(model);

  @override
  Future<Result<void, RpcError>> switchSession(String sessionPath) async =>
      const Success(null);
}

final class _TerminalFactory implements TerminalGatewayFactory {
  @override
  TerminalGateway create() => _TerminalGateway();
}

final class _TerminalGateway implements TerminalGateway {
  final _output = StreamController<List<int>>.broadcast();

  @override
  Stream<List<int>> get output => _output.stream;

  @override
  Future<void> kill() async => _output.close();

  @override
  void resize(int rows, int columns) {}

  @override
  void start({
    required String workingDirectory,
    int rows = 25,
    int columns = 80,
  }) {}

  @override
  void write(List<int> data) {}
}

final class _Folders implements FolderLister {
  @override
  Future<List<String>> subfolders(String root) async => const [];
}

final class _History implements SessionHistory {
  @override
  Future<List<SessionInfo>> sessionsFor(
    String cwd, {
    bool withTitle = false,
  }) async => const [];
}

final class _Notifier implements Notifier {
  @override
  Future<void> agentFinished({
    required String agentName,
    required String workspace,
  }) async {}

  @override
  Future<void> init() async {}
}

final class _FileSystem implements FileSystemReader {
  @override
  Future<List<FileNode>> children(String dirPath) async => const [];
}

final class _GitReader implements GitStatusReader {
  @override
  Future<GitInfo?> read(String path) async => null;
}

final class _Searcher implements FileSearcher {
  @override
  Future<List<String>> search(
    String root,
    String query, {
    int limit = 20,
  }) async => const [];
}

final class _Launcher implements AppLauncherGateway {
  @override
  Future<void> launch(LaunchableApp app, String path) async {}

  @override
  Future<void> openWithDefaultApp(String path) async {}

  @override
  Future<List<LaunchableApp>> probe() async => const [];
}

final class _Worktrees implements WorktreeManager {
  @override
  Future<Result<Worktree, WorktreeOpError>> add(
    String repoPath,
    String name,
  ) async => const Failure(WorktreeOpError('not implemented'));

  @override
  Future<bool> isBranchMerged(String repoPath, String branch) async => false;

  @override
  Future<List<Worktree>> list(String repoPath) async => const [];

  @override
  Future<WorktreeNamespace> namespace(String repoPath) async =>
      const WorktreeNamespace.empty();

  @override
  Future<Result<void, WorktreeOpError>> remove(
    String repoPath,
    String worktreePath,
    String branch,
  ) async => const Success(null);
}

final class _Mutator implements FileSystemMutator {
  @override
  Future<Result<void, String>> createDirectory(String path) async =>
      const Success(null);

  @override
  Future<Result<void, String>> createFile(String path) async =>
      const Success(null);

  @override
  Future<Result<void, String>> moveToTrash(String path) async =>
      const Success(null);

  @override
  Future<Result<void, String>> rename(String from, String to) async =>
      const Success(null);
}

final class _LspFactory implements LspClientFactory {
  @override
  LspClient create({required LspServerSpec spec, required String rootPath}) =>
      _LspClient(rootPath);
}

final class _LspClient implements LspClient {
  _LspClient(this.rootPath);
  final _diagnostics = StreamController<LspDiagnosticsBatch>.broadcast();

  @override
  Stream<LspDiagnosticsBatch> get diagnostics => _diagnostics.stream;

  @override
  bool get isRunning => false;

  @override
  final String rootPath;

  @override
  Future<void> didChange({
    required String path,
    required String text,
    required int version,
  }) async {}

  @override
  Future<void> didClose({required String path}) async {}

  @override
  Future<void> didOpen({required String path, required String text}) async {}

  @override
  void dispose() => unawaited(_diagnostics.close());

  @override
  Future<void> kill() async {}

  @override
  Future<Result<Object?, LspError>> request(
    String method,
    Map<String, dynamic> params,
  ) async => const Success(null);

  @override
  Future<Result<void, LspError>> start() async => const Success(null);
}
