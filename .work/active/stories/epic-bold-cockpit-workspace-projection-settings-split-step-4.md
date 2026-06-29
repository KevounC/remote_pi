---
id: epic-bold-cockpit-workspace-projection-settings-split-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-settings-split
depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
