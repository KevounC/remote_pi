---
id: epic-bold-cockpit-workspace-projection-workspace-document-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-workspace-document
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Implement pure workspace document commands for all pane/tab surgery

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / missing abstraction  
**Files**: `cockpit/lib/app/cockpit/domain/entities/workspace_document_commands.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_document.dart`, `cockpit/test/domain/workspace_document_commands_test.dart`, `cockpit/test/widget_test.dart`

## Current State
```dart
void moveTabToNewSplit(String srcPaneId, String tabId, String targetPaneId, SplitDir dir, {required bool before}) {
  final projectId = _selectedProjectId;
  final tree = _activeTree;
  if (projectId == null || tree == null) return;
  final src = findLeaf(tree, srcPaneId);
  final tgt = findLeaf(tree, targetPaneId);
  if (src == null || tgt == null || !src.tabs.contains(tabId)) return;
  // Removes tab from source, splits target, maybe removes empty source,
  // updates focus, ensures focus validity, and notifies inline.
}
```

## Target State
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
    // Pure tree/document transform only; no process disposal or notifyListeners.
  }
}
```

## Implementation Notes
- Port the high-risk operations first: `moveTabToPane`, `moveTabToNewSplit`, `moveTabToIndex`, `closeTab`, `closePane`, `splitPane`, `resizeSplit`, `selectTab`, `fillEmpty`, and `open/replace tab` helpers.
- Commands must be deterministic and side-effect free. They receive all fresh ids and tab descriptors from callers.
- Commands that remove tabs return `disposeTabIds`; the ViewModel/projection later disposes live sessions after applying the document.
- Keep no-op semantics identical: missing pane/tab, cross-pane self move of the last tab, and invalid target ids should leave the document unchanged.
- Tests should encode the current edge cases from `widget_test.dart` plus cross-pane last-tab removal, active-tab fallback, focused-pane fallback, split before/after, and index clamp.

## Acceptance Criteria
- [ ] All pane/tab mutation semantics currently embedded in `CockpitViewModel` have matching pure command tests.
- [ ] Commands import only domain files and Dart core libraries.
- [ ] Commands return explicit disposal effects instead of disposing live sessions.
- [ ] Existing split-tree tests still pass; new command tests cover `cockpit_viewmodel.dart:1009-1153` behavior before VM migration.
- [ ] `flutter test test/domain/workspace_document_commands_test.dart test/domain/workspace_pane_test.dart` passes.
- [ ] `flutter analyze` passes.

## Rollback
Delete `workspace_document_commands.dart` and its tests; leave the already-moved pane primitives and document codec in place because they are not behavior-coupled to command migration.
