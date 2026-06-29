---
id: epic-bold-cockpit-workspace-projection-workspace-document-step-2
kind: story
stage: review
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-workspace-document
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Add the canonical workspace document and v1 layout codec

**Priority**: High  
**Risk**: Medium  
**Source Lens**: single source of truth / missing abstraction  
**Files**: `cockpit/lib/app/cockpit/domain/entities/workspace_document.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_tab.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_layout_codec.dart`, `cockpit/lib/app/cockpit/domain/contracts/workspace_layout_store.dart`, `cockpit/test/domain/workspace_document_codec_test.dart`

## Current State
```dart
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
  return <String, dynamic>{'v': 1, 'focused': _focused[projectId], 'tree': paneNodeToJson(tree), 'sessions': sessions};
}
```

## Target State
```dart
final class WorkspaceDocument {
  const WorkspaceDocument({required this.projectId, required this.root, required this.focusedPaneId, required this.tabs, this.version = 1});

  final String projectId;
  final int version;
  final PaneNode root;
  final String focusedPaneId;
  final Map<String, WorkspaceTab> tabs;

  Map<String, dynamic> toPersistedJson() => WorkspaceLayoutCodec.encode(this);

  static WorkspaceDocument fromPersistedJson({required String projectId, required Map<String, dynamic> json}) =>
      WorkspaceLayoutCodec.decode(projectId: projectId, json: json);
}
```

```dart
final class WorkspaceLayoutCodec {
  static Map<String, dynamic> encode(WorkspaceDocument document) => <String, dynamic>{
    'v': 1,
    'focused': document.focusedPaneId,
    'tree': paneNodeToJson(document.root),
    'sessions': {for (final tab in document.tabs.values) tab.id: _tabToJson(tab)},
  };
}
```

## Implementation Notes
- Keep `WorkspaceLayoutStore`'s Map contract for this step; the store remains the Hive adapter and the domain codec owns the shape.
- Preserve current persisted keys exactly: `v`, `focused`, `tree`, `sessions`, `type`, `sub`, `title`, `path`, `sessionPath`, `auto_start_relay`, `preferred_model`, `preferred_thinking`.
- Keep corrupt/missing layout behavior compatible: invalid documents fall back to a single empty pane after the ViewModel realizes/sanitizes them.
- Use `ThinkingLevel` from domain for agent tab preferences; do not import UI session types.

## Acceptance Criteria
- [ ] Codec round-trips a current `v: 1` layout without changing JSON keys or semantic values.
- [ ] Codec decodes existing agent, terminal, viewer, and empty descriptors.
- [ ] Codec has tests for missing/unknown optional fields and invalid enum fallback to `ThinkingLevel.off`.
- [ ] `WorkspaceLayoutStore` stays an adapter boundary; Hive remains unaware of document internals.
- [ ] `flutter test test/domain/workspace_document_codec_test.dart` passes.
- [ ] `flutter analyze` passes.

## Rollback
Remove the new document/codec files and keep `_serializeLayout`, `_restoreProject`, and `_restoreSession` as the only layout-schema owners.

## Implementation notes
- Files changed: `cockpit/lib/app/cockpit/domain/entities/workspace_document.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_tab.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_layout_codec.dart`, `cockpit/test/domain/workspace_document_codec_test.dart`.
- Tests added: `cockpit/test/domain/workspace_document_codec_test.dart` covers v1 round-trip, agent/terminal/viewer/empty descriptors, missing optionals, invalid `preferred_thinking` fallback, and corrupt layout fallback.
- Discrepancies from design: none; `WorkspaceLayoutStore` remains an opaque `Map<String, dynamic>` boundary.
- Adjacent issues parked: none.
- Verification: `flutter test test/domain/workspace_document_codec_test.dart` could not start because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp` / `engine.realm`) even with `HOME=/tmp/pi-dart-home`; direct Dart formatting succeeded using the SDK binary.

