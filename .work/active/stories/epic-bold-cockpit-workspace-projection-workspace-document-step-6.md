---
id: epic-bold-cockpit-workspace-projection-workspace-document-step-6
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-workspace-document
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document-step-5]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 6: Extract the live workspace projection adapter from `CockpitViewModel`

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: code smell / ports and adapters  
**Files**: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart`, `cockpit/lib/app/cockpit/ui/session/pane_item.dart`, `cockpit/test/ui/workspace_projection_test.dart`

## Current State
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

## Target State
```dart
final class WorkspaceProjection {
  WorkspaceProjection({
    required RpcGatewayFactory rpcFactory,
    required TerminalGatewayFactory terminalFactory,
    required FileReader fileReader,
    required SessionHistory history,
    required Notifier notifier,
    required LspServerPool lsp,
  });

  PaneItem? item(String id) => _items[id];
  Iterable<PaneItem> itemsForProject(String projectId) => _items.values.where((item) => item.projectId == projectId);

  Future<bool> realize(WorkspaceTab tab, Project project) async { /* builds AgentSession, TerminalSession, FileViewerSession */ }
  void disposeTab(String id) { /* cancels watcher/debounce and disposes PaneItem */ }
  void disposeProject(WorkspaceDocument document) { for (final tabId in document.tabs.keys) disposeTab(tabId); }
  WorkspaceTab descriptorFor(PaneItem item, Project project) { /* replaces _sessionToJson ownership */ }
}
```

## Implementation Notes
- This is a UI/viewmodel adapter, not domain. It may import `PaneItem`, `AgentSession`, `TerminalSession`, `FileViewerSession`, file readers, process factories, notifications, and LSP.
- Move session construction, boot, file watcher ownership, `_sessionToJson` descriptor projection, `_captureSessionPath`, `_notifyIfNeeded`, and session disposal behind `WorkspaceProjection` methods where practical.
- Keep `CockpitViewModel.session(String id)` as a delegating getter for widgets.
- Keep git/worktree/project selection in `CockpitViewModel`; do not fold unrelated adapters into the projection in this step.
- This step is what makes `CockpitViewModel` a document coordinator instead of the owner of every live resource.

## Acceptance Criteria
- [ ] `CockpitViewModel` delegates live tab lookup, realization, descriptor projection, and disposal to `WorkspaceProjection`.
- [ ] `WorkspaceProjection` owns file-viewer watchers/debounces and disposes them deterministically.
- [ ] `WorkspaceProjection` owns live `PaneItem` lifecycle but does not mutate `WorkspaceDocument` directly.
- [ ] `CockpitViewModel` remains the owner of selected project, project list, git/worktree refresh, and document command application.
- [ ] `flutter test test/ui/workspace_projection_test.dart test/ui/cockpit_viewmodel_workspace_commands_test.dart` passes.
- [ ] `flutter analyze` passes.

## Rollback
Inline `WorkspaceProjection` methods back into `CockpitViewModel`, restore `_sessions`/watcher maps there, and keep the document/command integration from Steps 1-5.
