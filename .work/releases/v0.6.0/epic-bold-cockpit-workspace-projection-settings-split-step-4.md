---
id: epic-bold-cockpit-workspace-projection-settings-split-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-settings-split
depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-3]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 4: Extract the daemon settings projection

## Current State
```dart
class _DaemonsPanelState extends State<_DaemonsPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DaemonsViewModel>().reload();
    });
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<DaemonsViewModel>().refreshQuiet();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
```

## Target State
```dart
class DaemonSettingsPanel extends StatefulWidget {
  const DaemonSettingsPanel({super.key});

  @override
  State<DaemonSettingsPanel> createState() => _DaemonSettingsPanelState();
}

class _DaemonSettingsPanelState extends State<DaemonSettingsPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DaemonsViewModel>().reload();
    });
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<DaemonsViewModel>().refreshQuiet();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _openEditor([DaemonInfo? editing]) async {
    final vm = context.read<DaemonsViewModel>();
    final result = await showDaemonEditorDialog(context, editing: editing, daemons: vm.daemons);
    if (result == null || !mounted) return;
    editing == null
      ? await vm.create(result.cwd, name: result.name)
      : await vm.rename(editing, result.name);
  }
}
```

## Implementation Notes
- Move daemon fleet UI, `_DaemonTile`, `_DaemonActionsBar`, `_FleetButton`, `_fmtUptime`, and daemon state formatting with the daemon panel.
- Extract the daemon editor dialog/result into `ui/dialogs/daemon_editor_dialog.dart`; keep its `FilePicker` use at the UI edge.
- Preserve the polling owner and cancellation in the panel state; do not move timers into the ViewModel unless a separate behavior-changing feature scopes that.
- Preserve confirmation dialogs and mounted guards after `showDialog` before calling destructive actions.

## Acceptance Criteria
- [ ] Daemon fleet UI and editor dialog compile outside `settings_page.dart` and are imported by the route shell/panel.
- [ ] Poll timer starts only when the daemon panel is mounted and always cancels on dispose.
- [ ] Create, rename, start/stop/restart, fleet actions, supervisor restart, and remove call the same `DaemonsViewModel` methods as before.
- [ ] `FilePicker` remains behind the daemon dialog UI edge and is not pulled into domain/ViewModel code.
- [ ] `flutter test test/settings/daemon_settings_panel_test.dart` passes with fake timers or deterministic timer cancellation coverage.
- [ ] `flutter analyze` passes.

## Risk
Medium — daemon fleet actions are destructive and the panel owns a polling timer; incorrect movement can leak timers or call stale contexts.

## Rollback
Move daemon panel/dialog code back into `settings_page.dart`, restore private names, and keep Steps 1-3 intact.

## Implementation notes
- Extracted `DaemonSettingsPanel` to `cockpit/lib/app/settings/ui/categories/daemon_settings_panel.dart` and wired `SettingsPage` to import it for the daemons category.
- Moved daemon fleet actions, daemon tiles, state formatting, uptime formatting, and the 10s `Timer.periodic` polling lifecycle with the panel; `dispose()` cancels the timer and async dialog paths retain mounted guards before ViewModel calls.
- Extracted daemon editor UI and `DaemonEditorResult` to `cockpit/lib/app/settings/ui/dialogs/daemon_editor_dialog.dart`; `FilePicker` remains in that dialog UI edge.
- Added `cockpit/test/settings/daemon_settings_panel_test.dart` covering importability, ViewModel gateway behavior, post-frame reload, periodic refresh cancellation on dispose, row/fleet/supervisor actions, edit rename, and cancel-without-create behavior.
- Verification: `flutter pub get --offline` passed; targeted daemon panel test passed; touched-file analyze passed. Full `flutter analyze` is currently blocked by pre-existing/concurrent errors in `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, which this story was explicitly instructed not to edit.

## Review (2026-06-30, fast-lane)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 89658c5` — only owned files: `cockpit/lib/app/settings/ui/{settings_page.dart, categories/daemon_settings_panel.dart (new), dialogs/daemon_editor_dialog.dart}`, `cockpit/test/settings/daemon_settings_panel_test.dart` + this story. No collision with workspace-document agent's `cockpit_viewmodel.dart`/`workspace_document.dart`.
- Confirmed `DaemonSettingsPanel` extracted as its own StatefulWidget (`_DaemonSettingsPanelState` with post-frame reload, 10s periodic `refreshQuiet`, dispose timer cancellation, `_openEditor` via `showDaemonEditorDialog`); `settings_page.dart` dispatches `SettingsCategory.daemons => const DaemonSettingsPanel()`.
- `cd cockpit && flutter test test/settings/daemon_settings_panel_test.dart` (PUB_CACHE set, offline) — 7/7 pass (importability, VM reload/refreshQuiet semantics, panel lifecycle incl. dispose cancellation, daemon row + fleet/supervisor actions, edit dialog rename + cancel guard).
- NOTE: `flutter analyze` over the whole cockpit shows errors in `cockpit_viewmodel.dart` (`_focused`/`_trees` undefined) — these belong to the **workspace-document agent's uncommitted in-progress refactor** (replacing `_trees`/`_focused` with `_documents`), NOT to this story. This story's own committed files are clean. The tree will recompile once workspace-document-step-4 commits.
- Acceptance criteria satisfied: daemon projection extracted; lifecycle (load/refresh/dispose, mounted guards) preserved.
