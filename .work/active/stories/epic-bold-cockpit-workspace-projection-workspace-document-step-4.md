---
id: epic-bold-cockpit-workspace-projection-workspace-document-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-workspace-document
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Make `CockpitViewModel` load, save, and expose workspace documents

**Priority**: High  
**Risk**: Medium  
**Source Lens**: single source of truth / code smell  
**Files**: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_document.dart`, `cockpit/test/ui/cockpit_viewmodel_workspace_document_test.dart`

## Current State
```dart
final Map<String, PaneNode> _trees = <String, PaneNode>{};
final Map<String, String> _focused = <String, String>{};
final Map<String, Map<String, dynamic>?> _savedLayouts = <String, Map<String, dynamic>?>{};
```

## Target State
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

  document = document.filterTabs(restored, emptyTabFactory: () => _emptyTabDescriptor(project.id));
  _setDocument(document);
}
```

## Implementation Notes
- Replace `_trees` and `_focused` with `_documents`; keep `_selectedProjectId`, `_sessions`, git, file watcher, and save timer maps as projection/adapters for now.
- `_savedLayouts` may stay raw until activation so project boot remains lazy.
- `_initTree` becomes `_initDocument` and creates one empty `WorkspaceTab` descriptor plus one `LeafPane`.
- `_serializeLayout(projectId)` delegates to `_documents[projectId]?.toPersistedJson()` after refreshing document tab descriptors from the live session projection.
- `_restoreSession` should accept `WorkspaceTab`, not raw maps; it remains responsible for creating live `PaneItem`s and returns `false` for unavailable viewer files.
- Keep the old `tree(projectId)` and `focusedPaneId(projectId)` getters so widgets do not change in this step.

## Acceptance Criteria
- [ ] `CockpitViewModel` has one document map for pane tree + focused pane state; it no longer stores `_trees` and `_focused` as separate sources of truth.
- [ ] Loading a persisted v1 layout realizes live sessions from document tab descriptors and sanitizes missing viewer files exactly as before.
- [ ] Saving a layout emits the same v1 JSON shape for existing agent, terminal, viewer, and empty tabs.
- [ ] Project removal/worktree disposal cancels save timers and disposes live sessions through the document's tab ids.
- [ ] `flutter test test/ui/cockpit_viewmodel_workspace_document_test.dart` passes with fake repositories/adapters.
- [ ] `flutter analyze` passes.

## Rollback
Reintroduce `_trees` and `_focused`, restore `_restoreProject`, `_restoreSession`, `_serializeLayout`, and `_sessionToJson` to their pre-document implementations, and keep the domain document files unused until a later retry.

## Implementation notes
- Replaced the ViewModel's separate `_trees` and `_focused` maps with `_documents`, while preserving `tree(projectId)` and `focusedPaneId(projectId)` accessors for widgets.
- Restored persisted layouts through `WorkspaceDocument.fromPersistedJson`, realized typed `WorkspaceTab` descriptors into live sessions, and sanitized unrestorable tabs with `WorkspaceDocument.filterTabs` plus live empty placeholders.
- Saved layouts by refreshing document tab descriptors from live `PaneItem` projection before delegating to `WorkspaceDocument.toPersistedJson()`.
- Added ViewModel tests for document round-trip load/save/expose, focus clamping/accessors, and unrestorable viewer filtering.

## Review (2026-06-30, fast-lane)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 7201976` — only owned files: `cockpit_viewmodel.dart`, `workspace_document.dart`, `cockpit_viewmodel_workspace_document_test.dart` + story. No collision with settings-split agents.
- Confirmed `_trees`/`_focused` replaced by single `_documents: Map<String, WorkspaceDocument>`; `tree(projectId)`/`focusedPaneId(projectId)` delegate to it; `_setDocument` runs `ensureFocusValid()`; `WorkspaceDocument` has `fromPersistedJson`/`ensureFocusValid`/`filterTabs`.
- `cd cockpit && flutter test test/ui/cockpit_viewmodel_workspace_document_test.dart` (PUB_CACHE, offline) — 3/3 pass (round-trip load/save/expose; invalid-focus clamping; unrestorable-tab drop + live placeholder insertion).
- `flutter analyze` (whole cockpit, tree fully clean now) — **No issues found\!** (the earlier transient `_focused`/`_trees` errors were this agent's own in-progress refactor, now resolved).
- Acceptance criteria satisfied: CockpitViewModel loads/saves/exposes workspace documents via the WorkspaceDocument aggregate.
