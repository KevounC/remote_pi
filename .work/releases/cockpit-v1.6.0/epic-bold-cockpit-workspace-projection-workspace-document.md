---
id: epic-bold-cockpit-workspace-projection-workspace-document
kind: feature
stage: done
tags: [refactor, bold, cockpit]
parent: epic-bold-cockpit-workspace-projection
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Cockpit workspace — workspace as document (riskiest — design first)

## Brief
Workspace state as a pure document + command set: project selection, pane-tree
layout, live process refs, persisted layout. `CockpitViewModel` (1982 lines,
~20 mutable fields) becomes a thin projection; process/file/git/LSP adapters
subscribe around it. The riskiest part is the pane-tree surgery
(`cockpit_viewmodel.dart:1009-1153`, tab move/split/index) — that intricate
layout logic must become pure-document operations before the rest of the
projection can hang off it.

## Epic context
- Parent epic: `epic-bold-cockpit-workspace-projection`
- Position: riskiest child — the document shape is what the rest hangs on.
  Design FIRST.

## Foundation references
- Evidence: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart:51-140`,
  `:259-374` (`openFile`), `:1009-1153` (pane-tree surgery), `:1489-1580`
  (project activation/restoration).

<!-- /agile-workflow:refactor-design pins the document + command set. -->

## Design decisions
- Treat this as a behavior-preserving internal refactor. The cockpit UI, tab behavior, process boot/teardown behavior, and persisted layout JSON shape remain compatible with the current `v: 1` layout document.
- The canonical model lives in `cockpit/lib/app/cockpit/domain/entities/` and has no Flutter/UI/Hive/process dependencies. Runtime process refs (`AgentSession`, `TerminalSession`, file watchers, LSP handles) stay in the ViewModel/projection layer and are keyed by document tab ids.
- The document is the single source of truth for project workspace shape: pane tree, focused pane, tab order/active tab, and per-tab descriptors. Adapters project it to UI panes, persisted JSON, and live sessions.
- ID generation stays outside pure commands. Commands receive fresh ids from the ViewModel so the document layer remains deterministic and patchbay-portable.
- Direct scan rationale: the target is a bounded Cockpit feature module with one known god ViewModel and pure pane helper file, so refactor-design Phase 3 was done by direct code reading rather than fan-out. No `.agents/skills/refactor-conventions/` or patterns catalog exists in this checkout.

## Refactor Overview
The current workspace model is split across:

- `CockpitViewModel` mutable maps (`_selectedProjectId`, `_sessions`, `_trees`, `_focused`, `_savedLayouts`, `_saveTimers`) and many layout mutations.
- `ui/states/pane_node.dart`, which is pure but lives in `ui/` and only models the pane tree, not the workspace document or tabs.
- `WorkspaceLayoutStore`, which persists an opaque `Map<String, dynamic>`; the real layout schema is implied by private ViewModel methods `_restoreProject`, `_restoreSession`, `_serializeLayout`, and `_sessionToJson`.

The target is a domain-owned workspace document:

```dart
final class WorkspaceDocument {
  const WorkspaceDocument({
    required this.projectId,
    required this.root,
    required this.focusedPaneId,
    required this.tabs,
    this.version = 1,
  });

  final String projectId;
  final int version;
  final PaneNode root;
  final String focusedPaneId;
  final Map<String, WorkspaceTab> tabs;
}
```

`WorkspaceTab` is a descriptor, not the live process/widget object:

```dart
enum WorkspaceTabKind { empty, agent, terminal, viewer }

final class WorkspaceTab {
  const WorkspaceTab.agent({
    required this.id,
    required this.relativeSubpath,
    required this.title,
    this.sessionPath,
    this.autoStartRelay = false,
    this.preferredModelId,
    this.preferredThinking = ThinkingLevel.off,
  }) : kind = WorkspaceTabKind.agent,
       filePath = null;

  const WorkspaceTab.terminal({required this.id, required this.relativeSubpath, required this.title})
    : kind = WorkspaceTabKind.terminal,
      filePath = null,
      sessionPath = null,
      autoStartRelay = false,
      preferredModelId = null,
      preferredThinking = ThinkingLevel.off;

  const WorkspaceTab.viewer({required this.id, required this.filePath})
    : kind = WorkspaceTabKind.viewer,
      relativeSubpath = '',
      title = null,
      sessionPath = null,
      autoStartRelay = false,
      preferredModelId = null,
      preferredThinking = ThinkingLevel.off;

  const WorkspaceTab.empty({required this.id})
    : kind = WorkspaceTabKind.empty,
      relativeSubpath = '',
      title = 'New',
      filePath = null,
      sessionPath = null,
      autoStartRelay = false,
      preferredModelId = null,
      preferredThinking = ThinkingLevel.off;

  final String id;
  final WorkspaceTabKind kind;
  final String relativeSubpath;
  final String? title;
  final String? filePath;
  final String? sessionPath;
  final bool autoStartRelay;
  final String? preferredModelId;
  final ThinkingLevel preferredThinking;
}
```

Pure commands return a new document and explicit lifecycle effects for the projection layer:

```dart
final class WorkspaceCommandResult {
  const WorkspaceCommandResult({required this.document, this.disposeTabIds = const []});
  final WorkspaceDocument document;
  final List<String> disposeTabIds;
}
```

This keeps patchbay migration open: the document and commands are portable Dart domain state, while Cockpit-specific process/file/Hive adapters remain projections around it.

## Refactor Steps

### Step 1: Move the pane tree primitives into the Cockpit domain
**Priority**: High
**Risk**: Low
**Source Lens**: missing abstraction / pattern drift
**Files**: `cockpit/lib/app/cockpit/ui/states/pane_node.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_pane.dart`, `cockpit/test/widget_test.dart`, `cockpit/test/domain/workspace_pane_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-workspace-document-step-1`

**Current State**:
```dart
// cockpit/lib/app/cockpit/ui/states/pane_node.dart
enum SplitDir { vertical, horizontal }

sealed class PaneNode {
  const PaneNode(this.id);
  final String id;
}

final class LeafPane extends PaneNode {
  const LeafPane({required String id, required this.tabs, required this.active})
    : super(id);

  final List<String> tabs;
  final String active;
}
```

**Target State**:
```dart
// cockpit/lib/app/cockpit/domain/entities/workspace_pane.dart
enum SplitDir { vertical, horizontal }

sealed class PaneNode {
  const PaneNode(this.id);
  final String id;
}

final class LeafPane extends PaneNode {
  const LeafPane({required String id, required this.tabs, required this.active})
    : super(id);

  final List<String> tabs;
  final String active;

  LeafPane copyWith({List<String>? tabs, String? active}) =>
      LeafPane(id: id, tabs: tabs ?? this.tabs, active: active ?? this.active);
}

final class SplitPane extends PaneNode {
  const SplitPane({required String id, required this.dir, required this.a, required this.b, required this.frac})
    : super(id);

  final SplitDir dir;
  final PaneNode a;
  final PaneNode b;
  final double frac;
}
```

```dart
// cockpit/lib/app/cockpit/ui/states/pane_node.dart
export 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
```

**Implementation Notes**:
- Move the existing pure model, JSON helpers, and helper functions unchanged first; keep class names stable to minimize churn.
- Leave `ui/states/pane_node.dart` as a temporary export so current UI imports keep compiling while later steps migrate imports to the domain path.
- Move the split-tree tests out of `widget_test.dart` into `cockpit/test/domain/workspace_pane_test.dart` without weakening assertions.

**Acceptance Criteria**:
- [ ] `cockpit/test/domain/workspace_pane_test.dart` covers existing `leaves`, `splitLeaf`, `removeLeaf`, `updateLeaf`, `setFrac`, `reorderTabs`, and JSON round-trip behavior.
- [ ] No `workspace_pane.dart` import depends on Flutter, UI widgets, Hive, process adapters, or filesystem adapters.
- [ ] Existing UI compiles through the export shim.
- [ ] `flutter test test/domain/workspace_pane_test.dart` passes.
- [ ] `flutter analyze` passes.

**Rollback**: Move the file contents back to `ui/states/pane_node.dart`, restore the old test location, and remove `workspace_pane.dart`.

---

### Step 2: Add the canonical workspace document and v1 layout codec
**Priority**: High
**Risk**: Medium
**Source Lens**: single source of truth / missing abstraction
**Files**: `cockpit/lib/app/cockpit/domain/entities/workspace_document.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_tab.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_layout_codec.dart`, `cockpit/lib/app/cockpit/domain/contracts/workspace_layout_store.dart`, `cockpit/test/domain/workspace_document_codec_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-workspace-document-step-2`

**Current State**:
```dart
/// Persiste o layout do multiplexador de um projeto ... como um documento JSON opaco.
abstract class WorkspaceLayoutStore {
  Future<Map<String, dynamic>?> load(String projectId);
  Future<void> save(String projectId, Map<String, dynamic> document);
  Future<void> remove(String projectId);
}
```

```dart
Map<String, dynamic> _serializeLayout(String projectId) {
  final tree = _trees[projectId];
  final project = _projectById(projectId);
  if (tree == null || project == null) return const <String, dynamic>{};
  final sessions = <String, dynamic>{};
  for (final leaf in leaves(tree)) {
    for (final id in leaf.tabs) {
      final s = _sessions[id];
      if (s != null) sessions[id] = _sessionToJson(s, project);
    }
  }
  return <String, dynamic>{
    'v': 1,
    'focused': _focused[projectId],
    'tree': paneNodeToJson(tree),
    'sessions': sessions,
  };
}
```

**Target State**:
```dart
final class WorkspaceDocument {
  const WorkspaceDocument({
    required this.projectId,
    required this.root,
    required this.focusedPaneId,
    required this.tabs,
    this.version = 1,
  });

  final String projectId;
  final int version;
  final PaneNode root;
  final String focusedPaneId;
  final Map<String, WorkspaceTab> tabs;

  Map<String, dynamic> toPersistedJson() => WorkspaceLayoutCodec.encode(this);

  static WorkspaceDocument fromPersistedJson({
    required String projectId,
    required Map<String, dynamic> json,
  }) => WorkspaceLayoutCodec.decode(projectId: projectId, json: json);
}
```

```dart
final class WorkspaceLayoutCodec {
  static Map<String, dynamic> encode(WorkspaceDocument document) => <String, dynamic>{
    'v': 1,
    'focused': document.focusedPaneId,
    'tree': paneNodeToJson(document.root),
    'sessions': {
      for (final tab in document.tabs.values) tab.id: _tabToJson(tab),
    },
  };

  static WorkspaceDocument decode({required String projectId, required Map<String, dynamic> json}) {
    final treeJson = json['tree'];
    if (treeJson is! Map) return WorkspaceDocument.empty(projectId: projectId, tabId: 'a0', paneId: 'pane1');
    final tabs = _tabsFromJson((json['sessions'] as Map?)?.cast<String, dynamic>() ?? const {});
    final root = paneNodeFromJson(treeJson.cast<String, dynamic>());
    return WorkspaceDocument(projectId: projectId, root: root, focusedPaneId: json['focused'] as String? ?? leaves(root).first.id, tabs: tabs);
  }
}
```

**Implementation Notes**:
- Keep `WorkspaceLayoutStore`'s Map contract for this step; the store remains the Hive adapter and the domain codec owns the shape.
- Preserve current persisted keys exactly: `v`, `focused`, `tree`, `sessions`, `type`, `sub`, `title`, `path`, `sessionPath`, `auto_start_relay`, `preferred_model`, `preferred_thinking`.
- Keep corrupt/missing layout behavior compatible: invalid documents fall back to a single empty pane after the ViewModel realizes/sanitizes them.
- Use `ThinkingLevel` from domain for agent tab preferences; do not import UI session types.

**Acceptance Criteria**:
- [ ] Codec round-trips a current `v: 1` layout without changing JSON keys or semantic values.
- [ ] Codec decodes existing agent, terminal, viewer, and empty descriptors.
- [ ] Codec has tests for missing/unknown optional fields and invalid enum fallback to `ThinkingLevel.off`.
- [ ] `WorkspaceLayoutStore` stays an adapter boundary; Hive remains unaware of document internals.
- [ ] `flutter test test/domain/workspace_document_codec_test.dart` passes.
- [ ] `flutter analyze` passes.

**Rollback**: Remove the new document/codec files and keep `_serializeLayout`, `_restoreProject`, and `_restoreSession` as the only layout-schema owners.

---

### Step 3: Implement pure workspace document commands for all pane/tab surgery
**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction
**Files**: `cockpit/lib/app/cockpit/domain/entities/workspace_document_commands.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_document.dart`, `cockpit/test/domain/workspace_document_commands_test.dart`, `cockpit/test/widget_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-workspace-document-step-3`

**Current State**:
```dart
void moveTabToNewSplit(
  String srcPaneId,
  String tabId,
  String targetPaneId,
  SplitDir dir, {
  required bool before,
}) {
  final projectId = _selectedProjectId;
  final tree = _activeTree;
  if (projectId == null || tree == null) return;
  final src = findLeaf(tree, srcPaneId);
  final tgt = findLeaf(tree, targetPaneId);
  if (src == null || tgt == null || !src.tabs.contains(tabId)) return;

  final remaining = src.tabs.where((t) => t != tabId).toList();
  if (srcPaneId == targetPaneId && remaining.isEmpty) return;

  final newLeaf = LeafPane(id: _nid('pane'), tabs: [tabId], active: tabId);
  var t = tree;
  if (remaining.isNotEmpty) {
    t = updateLeaf(t, srcPaneId, (p) => p.copyWith(tabs: remaining, active: _activeAfter(src, tabId, remaining)));
  }
  t = splitLeaf(t, targetPaneId, dir, newLeaf, splitId: _nid('sp'), before: before);
  if (remaining.isEmpty) {
    t = removeLeaf(t, srcPaneId);
  }
  _setActiveTree(t);
  _focused[projectId] = newLeaf.id;
  _ensureFocusValid();
  notifyListeners();
}
```

**Target State**:
```dart
final class WorkspaceDocumentCommands {
  static WorkspaceCommandResult moveTabToNewSplit(
    WorkspaceDocument document, {
    required String srcPaneId,
    required String tabId,
    required String targetPaneId,
    required SplitDir dir,
    required bool before,
    required String newPaneId,
    required String newSplitId,
  }) {
    final src = findLeaf(document.root, srcPaneId);
    final target = findLeaf(document.root, targetPaneId);
    if (src == null || target == null || !src.tabs.contains(tabId)) {
      return WorkspaceCommandResult(document: document);
    }
    final remaining = src.tabs.where((id) => id != tabId).toList();
    if (srcPaneId == targetPaneId && remaining.isEmpty) {
      return WorkspaceCommandResult(document: document);
    }

    final newLeaf = LeafPane(id: newPaneId, tabs: [tabId], active: tabId);
    var root = document.root;
    if (remaining.isNotEmpty) {
      root = updateLeaf(root, srcPaneId, (pane) => pane.copyWith(tabs: remaining, active: _activeAfter(src, tabId, remaining)));
    }
    root = splitLeaf(root, targetPaneId, dir, newLeaf, splitId: newSplitId, before: before);
    if (remaining.isEmpty) root = removeLeaf(root, srcPaneId);

    return WorkspaceCommandResult(document: document.copyWith(root: root, focusedPaneId: newPaneId).ensureFocusValid());
  }
}
```

**Implementation Notes**:
- Port the high-risk operations first: `moveTabToPane`, `moveTabToNewSplit`, `moveTabToIndex`, `closeTab`, `closePane`, `splitPane`, `resizeSplit`, `selectTab`, `fillEmpty`, and `open/replace tab` helpers.
- Commands must be deterministic and side-effect free. They receive all fresh ids and tab descriptors from callers.
- Commands that remove tabs return `disposeTabIds`; the ViewModel/projection later disposes live sessions after applying the document.
- Keep no-op semantics identical: missing pane/tab, cross-pane self move of the last tab, and invalid target ids should leave the document unchanged.
- Tests should encode the current edge cases from `widget_test.dart` plus cross-pane last-tab removal, active-tab fallback, focused-pane fallback, split before/after, and index clamp.

**Acceptance Criteria**:
- [ ] All pane/tab mutation semantics currently embedded in `CockpitViewModel` have matching pure command tests.
- [ ] Commands import only domain files and Dart core libraries.
- [ ] Commands return explicit disposal effects instead of disposing live sessions.
- [ ] Existing split-tree tests still pass; new command tests cover `cockpit_viewmodel.dart:1009-1153` behavior before VM migration.
- [ ] `flutter test test/domain/workspace_document_commands_test.dart test/domain/workspace_pane_test.dart` passes.
- [ ] `flutter analyze` passes.

**Rollback**: Delete `workspace_document_commands.dart` and its tests; leave the already-moved pane primitives and document codec in place because they are not behavior-coupled to command migration.

---

### Step 4: Make `CockpitViewModel` load, save, and expose workspace documents
**Priority**: High
**Risk**: Medium
**Source Lens**: single source of truth / code smell
**Files**: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_document.dart`, `cockpit/test/ui/cockpit_viewmodel_workspace_document_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-workspace-document-step-4`

**Current State**:
```dart
final Map<String, PaneNode> _trees = <String, PaneNode>{};
final Map<String, String> _focused = <String, String>{};
final Map<String, Map<String, dynamic>?> _savedLayouts = <String, Map<String, dynamic>?>{};
```

```dart
Future<void> _restoreProject(String id, Map<String, dynamic> doc) async {
  final project = _projectById(id);
  final treeJson = doc['tree'];
  if (project == null || treeJson is! Map) {
    _initTree(id);
    return;
  }
  final sessionsJson = (doc['sessions'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
  final created = <String>{};
  for (final entry in sessionsJson.entries) {
    final desc = (entry.value as Map).cast<String, dynamic>();
    if (await _restoreSession(entry.key, desc, project)) {
      created.add(entry.key);
    }
  }
  var tree = paneNodeFromJson(treeJson.cast<String, dynamic>());
  _bumpSeqPast(sessionsJson.keys, tree);
  tree = _sanitizeTree(tree, created, id);
  _trees[id] = tree;
  final focused = doc['focused'] as String?;
  _focused[id] = (focused != null && findLeaf(tree, focused) != null) ? focused : leaves(tree).first.id;
}
```

**Target State**:
```dart
final Map<String, WorkspaceDocument> _documents = <String, WorkspaceDocument>{};
final Map<String, Map<String, dynamic>?> _savedLayouts = <String, Map<String, dynamic>?>{};

PaneNode? tree(String projectId) => _documents[projectId]?.root;
String? focusedPaneId(String projectId) => _documents[projectId]?.focusedPaneId;

void _setDocument(WorkspaceDocument document) {
  _documents[document.projectId] = document.ensureFocusValid();
}
```

```dart
Future<void> _restoreProject(String id, Map<String, dynamic> doc) async {
  final project = _projectById(id);
  if (project == null) {
    _initDocument(id);
    return;
  }
  var document = WorkspaceDocument.fromPersistedJson(projectId: id, json: doc);
  _bumpSeqPast(document.tabs.keys, document.root);

  final restored = <String>{};
  for (final tab in document.tabs.values) {
    if (await _restoreSession(tab, project)) restored.add(tab.id);
  }

  document = document.filterTabs(
    restored,
    emptyTabFactory: () => _emptyTabDescriptor(project.id),
  );
  _setDocument(document);
}
```

**Implementation Notes**:
- Replace `_trees` and `_focused` with `_documents`; keep `_selectedProjectId`, `_sessions`, git, file watcher, and save timer maps as projection/adapters for now.
- `_savedLayouts` may stay raw until activation so project boot remains lazy.
- `_initTree` becomes `_initDocument` and creates one empty `WorkspaceTab` descriptor plus one `LeafPane`.
- `_serializeLayout(projectId)` delegates to `_documents[projectId]?.toPersistedJson()` after refreshing document tab descriptors from the live session projection.
- `_restoreSession` should accept `WorkspaceTab`, not raw maps; it remains responsible for creating live `PaneItem`s and returns `false` for unavailable viewer files.
- Keep the old `tree(projectId)` and `focusedPaneId(projectId)` getters so widgets do not change in this step.

**Acceptance Criteria**:
- [ ] `CockpitViewModel` has one document map for pane tree + focused pane state; it no longer stores `_trees` and `_focused` as separate sources of truth.
- [ ] Loading a persisted v1 layout realizes live sessions from document tab descriptors and sanitizes missing viewer files exactly as before.
- [ ] Saving a layout emits the same v1 JSON shape for existing agent, terminal, viewer, and empty tabs.
- [ ] Project removal/worktree disposal cancels save timers and disposes live sessions through the document's tab ids.
- [ ] `flutter test test/ui/cockpit_viewmodel_workspace_document_test.dart` passes with fake repositories/adapters.
- [ ] `flutter analyze` passes.

**Rollback**: Reintroduce `_trees` and `_focused`, restore `_restoreProject`, `_restoreSession`, `_serializeLayout`, and `_sessionToJson` to their pre-document implementations, and keep the domain document files unused until a later retry.

---

### Step 5: Route all `CockpitViewModel` pane mutations through document commands
**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction
**Files**: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_document_commands.dart`, `cockpit/test/ui/cockpit_viewmodel_workspace_commands_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-workspace-document-step-5`

**Current State**:
```dart
void moveTabToIndex(String srcPaneId, String tabId, String targetPaneId, int index) {
  final projectId = _selectedProjectId;
  final tree = _activeTree;
  if (projectId == null || tree == null) return;
  final src = findLeaf(tree, srcPaneId);
  final tgt = findLeaf(tree, targetPaneId);
  if (src == null || tgt == null || !src.tabs.contains(tabId)) return;
  // tree mutation, focus mutation, notify all inline...
}
```

**Target State**:
```dart
void moveTabToIndex(String srcPaneId, String tabId, String targetPaneId, int index) {
  _applyWorkspaceCommand(
    (document) => WorkspaceDocumentCommands.moveTabToIndex(
      document,
      srcPaneId: srcPaneId,
      tabId: tabId,
      targetPaneId: targetPaneId,
      index: index,
    ),
  );
}

void _applyWorkspaceCommand(
  WorkspaceCommandResult Function(WorkspaceDocument document) command,
) {
  final document = _activeDocument;
  if (document == null) return;
  final result = command(document);
  _setDocument(result.document);
  for (final id in result.disposeTabIds) {
    _disposeSession(id);
  }
  _clearFocusedNotification();
  notifyListeners();
}
```

**Implementation Notes**:
- Migrate methods in a behavior-preserving order: selection/focus/resize first, then close/fill/split, then cross-pane moves, then `openFile` preview replacement logic.
- For methods that create live sessions (`newEmptyTab`, `newTabIn`, `splitPane`, `fillEmpty`, `openFile`), create the `WorkspaceTab` descriptor and live `PaneItem` together, then call the document command to place/select it. If a command no-ops, dispose the newly-created live item immediately.
- For methods that remove tabs/panes, apply the command first and then dispose `disposeTabIds`; this preserves the command's pure decision-making and keeps teardown owned by the projection layer.
- Keep current notification/save behavior: public methods still end with `notifyListeners()` through `_applyWorkspaceCommand`; `_restoring` still suppresses save during restore.
- Do not alter UI widgets except imports if needed.

**Acceptance Criteria**:
- [ ] `CockpitViewModel` no longer calls `updateLeaf`, `splitLeaf`, `removeLeaf`, `reorderTabs`, or `setFrac` directly in public pane/tab mutation methods.
- [ ] Existing UI behavior for split, close pane, close tab, drag-to-pane, drag-to-split, drag-to-index, resize, tab select, empty fill, and file preview replacement is covered by ViewModel tests or existing widget/domain tests.
- [ ] Commands remain pure and domain-only; live `PaneItem.dispose()` calls remain outside the domain layer.
- [ ] Debounced layout save still fires after structural mutations and not during restore.
- [ ] `flutter test test/domain/workspace_document_commands_test.dart test/ui/cockpit_viewmodel_workspace_commands_test.dart` passes.
- [ ] `flutter analyze` passes.

**Rollback**: Restore the direct ViewModel mutation bodies from before this step and keep the pure command layer unused while preserving Steps 1-4.

---

### Step 6: Extract the live workspace projection adapter from `CockpitViewModel`
**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / ports and adapters
**Files**: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart`, `cockpit/lib/app/cockpit/ui/session/pane_item.dart`, `cockpit/test/ui/workspace_projection_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-workspace-document-step-6`

**Current State**:
```dart
final Map<String, PaneItem> _sessions = <String, PaneItem>{};
final Map<String, StreamSubscription<void>> _fileWatchers = <String, StreamSubscription<void>>{};
final Map<String, Timer> _fileWatchDebounce = <String, Timer>{};

PaneItem? session(String id) => _sessions[id];

void _disposeSession(String id) {
  _fileWatchers.remove(id)?.cancel();
  _fileWatchDebounce.remove(id)?.cancel();
  final s = _sessions.remove(id);
  s?.dispose();
}
```

**Target State**:
```dart
final class WorkspaceProjection {
  WorkspaceProjection({
    required RpcGatewayFactory rpcFactory,
    required TerminalGatewayFactory terminalFactory,
    required FileReader fileReader,
    required SessionHistory history,
    required Notifier notifier,
    required LspServerPool lsp,
  }) : _rpcFactory = rpcFactory,
       _terminalFactory = terminalFactory,
       _fileReader = fileReader,
       _history = history,
       _notifier = notifier,
       _lsp = lsp;

  PaneItem? item(String id) => _items[id];
  Iterable<PaneItem> itemsForProject(String projectId) => _items.values.where((item) => item.projectId == projectId);

  Future<bool> realize(WorkspaceTab tab, Project project) async { /* builds AgentSession, TerminalSession, FileViewerSession */ }
  void disposeTab(String id) { /* cancels watcher/debounce and disposes PaneItem */ }
  void disposeProject(WorkspaceDocument document) { for (final tabId in document.tabs.keys) disposeTab(tabId); }
  WorkspaceTab descriptorFor(PaneItem item, Project project) { /* replaces _sessionToJson ownership */ }
}
```

**Implementation Notes**:
- This is a UI/viewmodel adapter, not domain. It may import `PaneItem`, `AgentSession`, `TerminalSession`, `FileViewerSession`, file readers, process factories, notifications, and LSP.
- Move session construction, boot, file watcher ownership, `_sessionToJson` descriptor projection, `_captureSessionPath`, `_notifyIfNeeded`, and session disposal behind `WorkspaceProjection` methods where practical.
- Keep `CockpitViewModel.session(String id)` as a delegating getter for widgets.
- Keep git/worktree/project selection in `CockpitViewModel`; do not fold unrelated adapters into the projection in this step.
- This step is what makes `CockpitViewModel` a document coordinator instead of the owner of every live resource.

**Acceptance Criteria**:
- [ ] `CockpitViewModel` delegates live tab lookup, realization, descriptor projection, and disposal to `WorkspaceProjection`.
- [ ] `WorkspaceProjection` owns file-viewer watchers/debounces and disposes them deterministically.
- [ ] `WorkspaceProjection` owns live `PaneItem` lifecycle but does not mutate `WorkspaceDocument` directly.
- [ ] `CockpitViewModel` remains the owner of selected project, project list, git/worktree refresh, and document command application.
- [ ] `flutter test test/ui/workspace_projection_test.dart test/ui/cockpit_viewmodel_workspace_commands_test.dart` passes.
- [ ] `flutter analyze` passes.

**Rollback**: Inline `WorkspaceProjection` methods back into `CockpitViewModel`, restore `_sessions`/watcher maps there, and keep the document/command integration from Steps 1-5.

## Implementation Order
1. `epic-bold-cockpit-workspace-projection-workspace-document-step-1` — domain-own the existing pane tree primitives.
2. `epic-bold-cockpit-workspace-projection-workspace-document-step-2` — add canonical workspace document + compatible v1 codec.
3. `epic-bold-cockpit-workspace-projection-workspace-document-step-3` — implement/test pure document commands for the pane surgery.
4. `epic-bold-cockpit-workspace-projection-workspace-document-step-4` — make `CockpitViewModel` load/save/expose documents.
5. `epic-bold-cockpit-workspace-projection-workspace-document-step-5` — route all pane/tab mutations through document commands.
6. `epic-bold-cockpit-workspace-projection-workspace-document-step-6` — extract live session/file/process projection from the ViewModel.

## Cycle check
Frontmatter dependency chain is linear and cycle-free by inspection:

- Step 1: `depends_on: []`
- Step 2: `depends_on: [step-1]`
- Step 3: `depends_on: [step-2]`
- Step 4: `depends_on: [step-3]`
- Step 5: `depends_on: [step-4]`
- Step 6: `depends_on: [step-5]`

No active item depends on any of these new story ids before creation, and the parent feature has no dependency on its children, so no back-edge is introduced.

## Not worth doing in this feature
- Rewriting Cockpit UI widgets or changing visible pane behavior. The UI should continue to consume `tree(projectId)`, `focusedPaneId(projectId)`, and `session(tabId)` while the model changes underneath.
- Changing the Hive `WorkspaceLayoutStore` persistence contract to a typed store. The Map boundary is acceptable while the domain codec owns the schema; changing adapter signatures can be a later cleanup.
- Adding patchbay-specific concepts. The document is intentionally generic and deterministic so a future patchbay migration can reuse or replace the projection layer without being blocked by Cockpit-specific process assumptions.

## Review — advanced to done (2026-06-30)

All 6 child stories `done`. Decomposition realized as designed; rollback notes
documented. Epic complete. (Advancing unblocks downstream stories that
depended on this epic-level completion.)
