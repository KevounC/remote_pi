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
import 'package:cockpit/app/cockpit/domain/entities/transcript_event.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document_commands.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/cockpit/domain/exceptions/rpc_error.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/exceptions/lsp_error.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('workspace commands are pure document transforms', () {
    final document = WorkspaceDocument(
      projectId: 'p1',
      focusedPaneId: 'main',
      root: const LeafPane(id: 'main', tabs: <String>['a', 'b'], active: 'b'),
      tabs: const <String, WorkspaceTab>{
        'a': WorkspaceTab.empty(id: 'a'),
        'b': WorkspaceTab.empty(id: 'b'),
      },
    );

    final result = WorkspaceDocumentCommands.closeTab(
      document,
      paneId: 'main',
      tabId: 'b',
      emptyTab: const WorkspaceTab.empty(id: 'unused'),
    );

    expect(findLeaf(document.root, 'main')!.tabs, <String>['a', 'b']);
    expect(document.tabs.keys, containsAll(<String>['a', 'b']));
    expect(findLeaf(result.document.root, 'main')!.tabs, <String>['a']);
    expect(result.document.tabs.containsKey('b'), isFalse);
    expect(result.disposeTabIds, <String>['b']);
  });

  test(
    'view model applies command results, clears focused notification, and notifies',
    () async {
      final project = await _project();
      final store = _LayoutStore(<String, Map<String, dynamic>?>{
        'p1': _twoPaneEmptyLayout(),
      });
      final vm = _viewModel(projects: <Project>[project], store: store);
      await vm.init();

      (vm.session('b')! as AgentSession).markUnseen();
      expect(vm.notificationCount('p1'), 1);
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.selectTab('left', 'b');

      final left = findLeaf(vm.tree('p1')!, 'left')!;
      expect(left.active, 'b');
      expect(vm.focusedPaneId('p1'), 'left');
      expect(vm.notificationCount('p1'), 0);
      expect(notifications, 1);

      await Future<void>.delayed(Duration.zero);
      vm.dispose();
    },
  );

  test(
    'close commands preserve tab lifecycle and dispose removed sessions',
    () async {
      final project = await _project();
      final store = _LayoutStore(<String, Map<String, dynamic>?>{
        'p1': _twoPaneEmptyLayout(),
      });
      final vm = _viewModel(projects: <Project>[project], store: store);
      await vm.init();

      vm.closeTab('left', 'b');

      expect(vm.session('b'), isNull);
      final leftAfterClose = findLeaf(vm.tree('p1')!, 'left')!;
      expect(leftAfterClose.tabs, <String>['a']);
      expect(leftAfterClose.active, 'a');

      vm.closePane('left');

      expect(vm.session('a'), isNull);
      expect(findLeaf(vm.tree('p1')!, 'left'), isNull);
      expect(findLeaf(vm.tree('p1')!, 'right')!.tabs, <String>['c']);
      expect(vm.focusedPaneId('p1'), 'right');

      await Future<void>.delayed(const Duration(milliseconds: 650));
      final savedSessions = store.saved['p1']!['sessions'] as Map;
      expect(savedSessions.containsKey('a'), isFalse);
      expect(savedSessions.containsKey('b'), isFalse);
      expect(savedSessions.containsKey('c'), isTrue);

      await Future<void>.delayed(Duration.zero);
      vm.dispose();
    },
  );

  test(
    'split, move, resize, and fill empty stay behavior-compatible',
    () async {
      final project = await _project();
      final store = _LayoutStore(<String, Map<String, dynamic>?>{
        'p1': _singleEmptyLayout(),
      });
      final vm = _viewModel(projects: <Project>[project], store: store);
      await vm.init();

      vm.fillEmpty('main', 'empty', 'tools', terminal: true);
      final terminalId = findLeaf(vm.tree('p1')!, 'main')!.active;
      expect(vm.session('empty'), isNull);
      expect(vm.session(terminalId), isA<TerminalSession>());

      vm.newEmptyTab('main');
      final mainWithEmpty = findLeaf(vm.tree('p1')!, 'main')!;
      final emptyId = mainWithEmpty.active;
      expect(mainWithEmpty.tabs, <String>[terminalId, emptyId]);
      expect(vm.session(emptyId), isA<AgentSession>());

      vm.moveTabToIndex('main', emptyId, 'main', 0);
      expect(findLeaf(vm.tree('p1')!, 'main')!.tabs, <String>[
        emptyId,
        terminalId,
      ]);

      vm.splitPane('main', SplitDir.vertical, 'tools');
      final split = vm.tree('p1')! as SplitPane;
      expect(split.dir, SplitDir.vertical);
      expect(split.frac, 0.5);
      final newPane = leaves(split).singleWhere((leaf) => leaf.id != 'main');
      expect(vm.focusedPaneId('p1'), newPane.id);

      vm.moveTabToPane('main', emptyId, newPane.id);
      expect(findLeaf(vm.tree('p1')!, 'main')!.tabs, <String>[terminalId]);
      expect(findLeaf(vm.tree('p1')!, newPane.id)!.tabs, contains(emptyId));
      expect(vm.focusedPaneId('p1'), newPane.id);

      vm.resizeSplit(split.id, 0.99);
      expect((vm.tree('p1')! as SplitPane).frac, 0.84);

      await Future<void>.delayed(Duration.zero);
      vm.dispose();
    },
  );

  test(
    'openFile routes preview replacement through document commands',
    () async {
      final project = await _project();
      final store = _LayoutStore(<String, Map<String, dynamic>?>{
        'p1': _singleEmptyLayout(),
      });
      final vm = _viewModel(projects: <Project>[project], store: store);
      await vm.init();

      final firstPath = '${project.path}/first.md';
      final secondPath = '${project.path}/second.md';
      final pinnedPath = '${project.path}/pinned.md';

      await vm.openFile(firstPath);
      final firstLeaf = findLeaf(vm.tree('p1')!, 'main')!;
      final viewerId = firstLeaf.active;
      expect(vm.session('empty'), isNull);
      expect(
        vm.session(viewerId),
        isA<FileViewerSession>()
            .having((viewer) => viewer.path, 'path', firstPath)
            .having((viewer) => viewer.isPreview, 'isPreview', isTrue),
      );

      await vm.openFile(secondPath);
      final reusedLeaf = findLeaf(vm.tree('p1')!, 'main')!;
      expect(reusedLeaf.tabs, <String>[viewerId]);
      expect(
        vm.session(viewerId),
        isA<FileViewerSession>().having(
          (viewer) => viewer.path,
          'path',
          secondPath,
        ),
      );

      await vm.openFile(pinnedPath, isPreview: false);
      final pinnedLeaf = findLeaf(vm.tree('p1')!, 'main')!;
      expect(pinnedLeaf.tabs, hasLength(2));
      expect(pinnedLeaf.active, isNot(viewerId));
      expect(vm.session(pinnedLeaf.active), isA<FileViewerSession>());

      await Future<void>.delayed(const Duration(milliseconds: 650));
      final savedSessions = store.saved['p1']!['sessions'] as Map;
      expect(savedSessions.containsKey(viewerId), isTrue);
      expect(savedSessions[pinnedLeaf.active], <String, dynamic>{
        'type': 'viewer',
        'path': pinnedPath,
      });

      await Future<void>.delayed(Duration.zero);
      vm.dispose();
    },
  );
}

Map<String, dynamic> _singleEmptyLayout() => <String, dynamic>{
  'v': 1,
  'focused': 'main',
  'tree': <String, dynamic>{
    'k': 'leaf',
    'id': 'main',
    'tabs': <String>['empty'],
    'active': 'empty',
  },
  'sessions': <String, dynamic>{
    'empty': <String, dynamic>{'type': 'empty', 'title': 'New'},
  },
};

Map<String, dynamic> _twoPaneEmptyLayout() => <String, dynamic>{
  'v': 1,
  'focused': 'right',
  'tree': <String, dynamic>{
    'k': 'split',
    'id': 'root',
    'dir': 'vertical',
    'frac': 0.5,
    'a': <String, dynamic>{
      'k': 'leaf',
      'id': 'left',
      'tabs': <String>['a', 'b'],
      'active': 'a',
    },
    'b': <String, dynamic>{
      'k': 'leaf',
      'id': 'right',
      'tabs': <String>['c'],
      'active': 'c',
    },
  },
  'sessions': <String, dynamic>{
    'a': <String, dynamic>{'type': 'empty', 'title': 'New'},
    'b': <String, dynamic>{'type': 'empty', 'title': 'New'},
    'c': <String, dynamic>{'type': 'empty', 'title': 'New'},
  },
};

Future<Project> _project() async {
  final dir = await Directory.systemTemp.createTemp(
    'cockpit-vm-commands-test-',
  );
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
  final Map<String, Map<String, dynamic>> saved =
      <String, Map<String, dynamic>>{};

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
  Future<FileView> read(String path) async =>
      FileViewText('content for $path', language: 'text');

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
  Future<Result<List<CockpitTranscriptEvent>, RpcError>> getMessages({
    required String sessionId,
  }) async => const Success([]);

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
  Future<List<String>> subfolders(String root) async => const <String>[];
}

final class _History implements SessionHistory {
  @override
  Future<List<SessionInfo>> sessionsFor(
    String cwd, {
    bool withTitle = false,
  }) async => const <SessionInfo>[];
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
  Future<List<FileNode>> children(String dirPath) async => const <FileNode>[];
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
  }) async => const <String>[];
}

final class _Launcher implements AppLauncherGateway {
  @override
  Future<void> launch(LaunchableApp app, String path) async {}

  @override
  Future<void> openWithDefaultApp(String path) async {}

  @override
  Future<List<LaunchableApp>> probe() async => const <LaunchableApp>[];
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
  Future<List<Worktree>> list(String repoPath) async => const <Worktree>[];

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
