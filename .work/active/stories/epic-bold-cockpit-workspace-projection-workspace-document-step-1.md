---
id: epic-bold-cockpit-workspace-projection-workspace-document-step-1
kind: story
stage: review
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-workspace-document
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Move the pane tree primitives into the Cockpit domain

**Priority**: High  
**Risk**: Low  
**Source Lens**: missing abstraction / pattern drift  
**Files**: `cockpit/lib/app/cockpit/ui/states/pane_node.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_pane.dart`, `cockpit/test/widget_test.dart`, `cockpit/test/domain/workspace_pane_test.dart`

## Current State
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

## Target State
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
```

```dart
// cockpit/lib/app/cockpit/ui/states/pane_node.dart
export 'package:cockpit/app/cockpit/domain/entities/workspace_pane.dart';
```

## Implementation Notes
- Move the existing pure model, JSON helpers, and helper functions unchanged first; keep class names stable to minimize churn.
- Leave `ui/states/pane_node.dart` as a temporary export so current UI imports keep compiling while later steps migrate imports to the domain path.
- Move the split-tree tests out of `widget_test.dart` into `cockpit/test/domain/workspace_pane_test.dart` without weakening assertions.

## Acceptance Criteria
- [ ] `cockpit/test/domain/workspace_pane_test.dart` covers existing `leaves`, `splitLeaf`, `removeLeaf`, `updateLeaf`, `setFrac`, `reorderTabs`, and JSON round-trip behavior.
- [ ] No `workspace_pane.dart` import depends on Flutter, UI widgets, Hive, process adapters, or filesystem adapters.
- [ ] Existing UI compiles through the export shim.
- [ ] `flutter test test/domain/workspace_pane_test.dart` passes.
- [ ] `flutter analyze` passes.

## Rollback
Move the file contents back to `ui/states/pane_node.dart`, restore the old test location, and remove `workspace_pane.dart`.

## Implementation Notes
Moved the pure pane tree model/helpers into `cockpit/lib/app/cockpit/domain/entities/workspace_pane.dart` and reduced `cockpit/lib/app/cockpit/ui/states/pane_node.dart` to a temporary export shim so existing UI imports continue to compile. Moved the split-tree tests out of `cockpit/test/widget_test.dart` into `cockpit/test/domain/workspace_pane_test.dart` without weakening coverage; `widget_test.dart` now keeps only the file-icon and setup-gate tests.

Verification attempted:
- `dart format ...` and `flutter test test/domain/workspace_pane_test.dart` could not start because the installed Flutter tool tried to update `/opt/flutter/bin/cache/*` and the cache is read-only in this environment (`Read-only file system`). No test assertions were weakened or skipped in code; this is an environment/toolchain blocker.
