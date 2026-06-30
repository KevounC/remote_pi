import 'dart:async';
import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_tab.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

typedef WorkspaceProjectionTurnEnd = void Function(AgentSession session);
typedef WorkspaceProjectionPreferenceChanged = void Function(String projectId);

/// Live projection of a persisted [WorkspaceDocument] into disposable UI tabs.
///
/// The document owns pane shape and tab descriptors. This adapter owns the live
/// [PaneItem] instances behind those descriptors: agent RPC sessions, terminal
/// PTYs, file viewer buffers, and file-watch debounce timers.
final class WorkspaceProjection {
  WorkspaceProjection({
    required RpcGatewayFactory rpcFactory,
    required TerminalGatewayFactory terminalFactory,
    required FileReader fileReader,
    required SessionHistory history,
    required Notifier notifier,
    required this.lsp,
    VoidCallback? onChanged,
    WorkspaceProjectionTurnEnd? onAgentTurnEnd,
    WorkspaceProjectionPreferenceChanged? onPreferenceChanged,
  }) : _rpcFactory = rpcFactory,
       _terminalFactory = terminalFactory,
       _fileReader = fileReader,
       _history = history,
       _notifier = notifier,
       _onChanged = onChanged ?? _noop,
       _onAgentTurnEnd = onAgentTurnEnd,
       _onPreferenceChanged = onPreferenceChanged;

  final RpcGatewayFactory _rpcFactory;
  final TerminalGatewayFactory _terminalFactory;
  final FileReader _fileReader;
  final SessionHistory _history;
  final Notifier _notifier;

  /// Kept as part of the projection boundary for file-viewer/LSP coordination.
  final LspServerPool lsp;

  final VoidCallback _onChanged;
  final WorkspaceProjectionTurnEnd? _onAgentTurnEnd;
  final WorkspaceProjectionPreferenceChanged? _onPreferenceChanged;

  final Map<String, PaneItem> _items = <String, PaneItem>{};
  final Map<String, StreamSubscription<void>> _fileWatchers =
      <String, StreamSubscription<void>>{};
  final Map<String, Timer> _fileWatchDebounce = <String, Timer>{};

  static void _noop() {}

  PaneItem? item(String id) => _items[id];

  Iterable<PaneItem> get items => _items.values;

  Iterable<PaneItem> itemsForProject(String projectId) =>
      _items.values.where((item) => item.projectId == projectId);

  int notificationCount(String projectId) =>
      itemsForProject(projectId).where((item) => item.unseenFinish).length;

  Future<bool> realize(WorkspaceTab tab, Project project) async {
    String cwdOf() {
      final sub = tab.relativeSubpath;
      return sub.isEmpty ? project.path : '${project.path}/$sub';
    }

    switch (tab.kind) {
      case WorkspaceTabKind.terminal:
        createTerminal(
          id: tab.id,
          projectId: project.id,
          workingDirectory: cwdOf(),
          title: tab.title,
        );
        return true;
      case WorkspaceTabKind.viewer:
        final path = tab.filePath;
        if (path == null) return false;
        return (await createViewer(
              id: tab.id,
              projectId: project.id,
              path: path,
            )) !=
            null;
      case WorkspaceTabKind.empty:
        createEmpty(id: tab.id, projectId: project.id, title: tab.title);
        return true;
      case WorkspaceTabKind.agent:
        createAgent(
          id: tab.id,
          project: project,
          workingDirectory: cwdOf(),
          title: tab.title,
          autoStartRelay: tab.autoStartRelay,
          restoreSessionPath: tab.sessionPath,
          preferredModelId: tab.preferredModelId,
          preferredThinking: tab.preferredThinking,
        );
        return true;
    }
  }

  AgentSession createEmpty({
    required String id,
    required String projectId,
    String? title,
  }) {
    final session = AgentSession(
      id: id,
      projectId: projectId,
      workingDirectory: '',
      factory: _rpcFactory,
      title: title ?? 'New',
    );
    _items[session.id] = session;
    return session;
  }

  TerminalSession createTerminal({
    required String id,
    required String projectId,
    required String workingDirectory,
    String? title,
  }) {
    final terminal = TerminalSession(
      id: id,
      projectId: projectId,
      workingDirectory: workingDirectory,
      gateway: _terminalFactory.create(),
      title: title,
    );
    _items[terminal.id] = terminal;
    return terminal;
  }

  AgentSession createAgent({
    required String id,
    required Project project,
    required String workingDirectory,
    String? title,
    bool autoStartRelay = false,
    String? restoreSessionPath,
    String? preferredModelId,
    ThinkingLevel preferredThinking = ThinkingLevel.off,
  }) {
    final session =
        AgentSession(
            id: id,
            projectId: project.id,
            workingDirectory: workingDirectory,
            factory: _rpcFactory,
            title: title,
            autoStartRelay: autoStartRelay,
          )
          ..preferredModelId = preferredModelId
          ..preferredThinking = preferredThinking;
    session.onTurnEnd = () => _onAgentTurnEnd?.call(session);
    session.onPreferenceChanged = () => _onPreferenceChanged?.call(project.id);
    _items[session.id] = session;
    unawaited(_bootAgent(session, project, restoreSessionPath));
    return session;
  }

  Future<FileViewerSession?> createViewer({
    required String id,
    required String projectId,
    required String path,
    bool isPreview = false,
  }) async {
    final view = await _fileReader.read(path);
    if (view is FileViewUnsupported) return null;
    final viewer = FileViewerSession(
      id: id,
      projectId: projectId,
      path: path,
      view: view,
      isPreview: isPreview,
    );
    _items[viewer.id] = viewer;
    _watchFileViewer(viewer);
    return viewer;
  }

  Future<bool> replaceViewerPath(String id, String path) async {
    final fresh = await _fileReader.read(path);
    if (fresh is FileViewUnsupported) return false;
    final current = _items[id];
    if (current is! FileViewerSession) return false;
    current.path = path;
    current.view = fresh;
    current.dirty = false;
    current.notifyItemChanged();
    _watchFileViewer(current);
    _onChanged();
    return true;
  }

  Future<bool> saveViewer(String id, String content) async {
    final viewer = _items[id];
    if (viewer is! FileViewerSession) return false;
    final ok = await _fileReader.write(viewer.path, content);
    if (!ok) return false;
    final fresh = await _fileReader.read(viewer.path);
    final current = _items[id];
    if (current is FileViewerSession && fresh is! FileViewUnsupported) {
      current.view = fresh;
      _onChanged();
    }
    return true;
  }

  Future<void> retargetViewersUnder(String from, String to) async {
    for (final item in List<PaneItem>.of(_items.values)) {
      if (item is! FileViewerSession || !_isUnder(item.path, from)) continue;
      final newPath = item.path == from
          ? to
          : '$to${item.path.substring(from.length)}';
      item.retarget(newPath);
      final fresh = await _fileReader.read(newPath);
      final current = _items[item.id];
      if (current is! FileViewerSession) continue;
      if (fresh is! FileViewUnsupported) current.view = fresh;
      _watchFileViewer(current);
    }
    _onChanged();
  }

  void clearUnseen(String id) {
    final item = _items[id];
    if (item != null && item.unseenFinish) item.clearUnseen();
  }

  void disposeTab(String id) {
    _fileWatchers.remove(id)?.cancel();
    _fileWatchDebounce.remove(id)?.cancel();
    final item = _items.remove(id);
    item?.dispose();
  }

  void disposeProject(WorkspaceDocument document) {
    for (final tabId in document.tabs.keys) {
      disposeTab(tabId);
    }
  }

  WorkspaceTab descriptorFor(PaneItem item, Project project) {
    if (item is TerminalSession) {
      return WorkspaceTab.terminal(
        id: item.id,
        relativeSubpath: _subOf(item.workingDirectory, project.path),
        title: item.title,
      );
    }
    if (item is FileViewerSession) {
      return WorkspaceTab.viewer(id: item.id, filePath: item.path);
    }
    final agent = item as AgentSession;
    if (agent.status == AgentStatus.empty) {
      return WorkspaceTab.empty(id: agent.id, title: agent.title);
    }
    return WorkspaceTab.agent(
      id: agent.id,
      relativeSubpath: _subOf(agent.workingDirectory, project.path),
      title: agent.title,
      sessionPath: agent.sessionPath,
      autoStartRelay: agent.autoStartRelay,
      preferredModelId: agent.preferredModelId,
      preferredThinking: agent.preferredThinking,
    );
  }

  WorkspaceDocument documentWithLiveTabs(
    Project project,
    WorkspaceDocument document,
  ) {
    final tabs = <String, WorkspaceTab>{};
    for (final leaf in leaves(document.root)) {
      for (final id in leaf.tabs) {
        final item = _items[id];
        final tab = item == null
            ? document.tabs[id]
            : descriptorFor(item, project);
        if (tab != null) tabs[id] = tab;
      }
    }
    return document.copyWith(tabs: tabs);
  }

  Future<void> captureSessionPath(AgentSession session) async {
    final baseline = session.sessionBaseline;
    if (baseline == null || session.sessionPath != null) return;
    final now = await _history.sessionsFor(session.workingDirectory);
    final fresh = now.where((entry) => !baseline.contains(entry.path)).toList();
    if (fresh.isEmpty) return;
    fresh.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    session.sessionPath = fresh.first.path;
    _onChanged();
  }

  Future<void> notifyIfNeeded(
    AgentSession session, {
    required bool isActiveTab,
    required bool notificationsEnabled,
    required String workspace,
  }) async {
    if (!isActiveTab) {
      session.markUnseen();
      _onChanged();
    }

    if (!notificationsEnabled) return;

    final windowFocused = await windowManager.isFocused();
    if (!windowFocused) {
      await _notifier.agentFinished(
        agentName: session.title,
        workspace: workspace,
      );
    }
  }

  void dispose() {
    for (final watcher in _fileWatchers.values) {
      watcher.cancel();
    }
    _fileWatchers.clear();
    for (final timer in _fileWatchDebounce.values) {
      timer.cancel();
    }
    _fileWatchDebounce.clear();
    for (final item in _items.values) {
      item.dispose();
    }
    _items.clear();
  }

  Future<void> _bootAgent(
    AgentSession session,
    Project project,
    String? restoreSessionPath,
  ) async {
    session.sessionBaseline = (await _history.sessionsFor(
      session.workingDirectory,
    )).map((entry) => entry.path).toSet();
    await session.boot(
      environment: _buildDirectConfig(session, project),
      restoreSessionPath: restoreSessionPath,
    );
  }

  Map<String, String> _buildDirectConfig(
    AgentSession session,
    Project project,
  ) {
    return {
      'REMOTE_PI_DIRECT_CONFIG': jsonEncode(<String, dynamic>{
        'agent_name': session.title,
        'workspace': project.name,
        'auto_start_relay': session.autoStartRelay,
      }),
      'REMOTE_PI_DAEMON': '1',
    };
  }

  void _watchFileViewer(FileViewerSession viewer) {
    // A/V live reload is disabled: refreshing would recreate the player mid-play.
    if (viewer.view is FileViewAudio || viewer.view is FileViewVideo) return;
    final id = viewer.id;
    _fileWatchers.remove(id)?.cancel();
    _fileWatchers[id] = _fileReader.watch(viewer.path).listen((_) {
      _fileWatchDebounce[id]?.cancel();
      _fileWatchDebounce[id] = Timer(
        const Duration(milliseconds: 120),
        () async {
          _fileWatchDebounce.remove(id);
          if (_items[id] is! FileViewerSession) return;
          final fresh = await _fileReader.read(viewer.path);
          if (fresh is FileViewUnsupported) return;
          final current = _items[id];
          if (current is! FileViewerSession) return;
          current.view = fresh;
          current.notifyItemChanged();
          _onChanged();
        },
      );
    }, onError: (_) {});
  }

  bool _isUnder(String path, String root) =>
      path == root || path.startsWith('$root/');

  String _subOf(String cwd, String root) {
    final c = cwd.replaceAll('\\', '/');
    final r = root.replaceAll('\\', '/');
    if (c == r) return '';
    final prefix = r.endsWith('/') ? r : '$r/';
    return c.startsWith(prefix) ? c.substring(prefix.length) : '';
  }
}
