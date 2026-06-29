---
id: epic-bold-cockpit-workspace-projection-workspace-document-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-workspace-document
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Route all `CockpitViewModel` pane mutations through document commands

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / missing abstraction  
**Files**: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_document_commands.dart`, `cockpit/test/ui/cockpit_viewmodel_workspace_commands_test.dart`

## Current State
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

## Target State
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

void _applyWorkspaceCommand(WorkspaceCommandResult Function(WorkspaceDocument document) command) {
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

## Implementation Notes
- Migrate methods in a behavior-preserving order: selection/focus/resize first, then close/fill/split, then cross-pane moves, then `openFile` preview replacement logic.
- For methods that create live sessions (`newEmptyTab`, `newTabIn`, `splitPane`, `fillEmpty`, `openFile`), create the `WorkspaceTab` descriptor and live `PaneItem` together, then call the document command to place/select it. If a command no-ops, dispose the newly-created live item immediately.
- For methods that remove tabs/panes, apply the command first and then dispose `disposeTabIds`; this preserves the command's pure decision-making and keeps teardown owned by the projection layer.
- Keep current notification/save behavior: public methods still end with `notifyListeners()` through `_applyWorkspaceCommand`; `_restoring` still suppresses save during restore.
- Do not alter UI widgets except imports if needed.

## Acceptance Criteria
- [ ] `CockpitViewModel` no longer calls `updateLeaf`, `splitLeaf`, `removeLeaf`, `reorderTabs`, or `setFrac` directly in public pane/tab mutation methods.
- [ ] Existing UI behavior for split, close pane, close tab, drag-to-pane, drag-to-split, drag-to-index, resize, tab select, empty fill, and file preview replacement is covered by ViewModel tests or existing widget/domain tests.
- [ ] Commands remain pure and domain-only; live `PaneItem.dispose()` calls remain outside the domain layer.
- [ ] Debounced layout save still fires after structural mutations and not during restore.
- [ ] `flutter test test/domain/workspace_document_commands_test.dart test/ui/cockpit_viewmodel_workspace_commands_test.dart` passes.
- [ ] `flutter analyze` passes.

## Rollback
Restore the direct ViewModel mutation bodies from before this step and keep the pure command layer unused while preserving Steps 1-4.
