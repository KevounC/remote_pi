---
id: epic-bold-cockpit-workspace-projection-settings-split-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-settings-split
depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Extract the schedule settings projection and leave `SettingsPage` as a route shell

## Current State
```dart
class _AgendamentosPanelState extends State<_AgendamentosPanel> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CronViewModel>().reload();
    });
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<CronViewModel>().refreshQuiet();
    });
  }

  Future<void> _openEditor() async {
    final vm = context.read<CronViewModel>();
    if (vm.daemons.isEmpty) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CronEditorDialog(vm: vm),
    );
    if (created == true && mounted) await vm.reload();
  }
}

class _CronEditorDialog extends StatefulWidget { /* cron form + preview */ }
class _CronLogDialog extends StatefulWidget { /* cron.jsonl fetch */ }
```

## Target State
```dart
class SettingsCategoryPanel extends StatelessWidget {
  const SettingsCategoryPanel({required this.category, super.key});
  final SettingsCategory category;

  @override
  Widget build(BuildContext context) => switch (category) {
    SettingsCategory.appearance => const AppearanceSettingsPanel(),
    SettingsCategory.languages => const LanguageSettingsPanel(),
    SettingsCategory.notifications => const NotificationSettingsPanel(),
    SettingsCategory.connectivity => const ConnectivitySettingsPanel(),
    SettingsCategory.daemons => const DaemonSettingsPanel(),
    SettingsCategory.scheduling => const ScheduleSettingsPanel(),
  };
}
```

```dart
// settings/ui/settings_page.dart after the split
class SettingsPage extends StatefulWidget { /* route state only */ }
class _SettingsPageState extends State<SettingsPage> { /* env gate + selected category + SettingsShell */ }
```

## Implementation Notes
- Move `_AgendamentosPanel`, `_CronTile`, `_CronMeta`, cron dialogs, `_CronOptionSwitch`, `_ExampleChip`, cron formatting helpers, and cron-result view into schedule-specific files.
- Keep `CronViewModel` page-scoped in `settings_module.dart`; the schedule panel owns only UI lifecycle/timers/dialogs.
- Use `ScheduleSettingsPanel` in code, even if visible labels remain `Schedules`; avoid carrying the Portuguese `Agendamentos` class name into the split.
- Add `settings_category_panel.dart` as the one switch from registry value to panel widget. That keeps `settings_page.dart` as the route shell and makes future patchbay replacement of panels localized.

## Acceptance Criteria
- [ ] `settings_page.dart` contains only the route widget/state and no category panel, tile, dialog, or shared component classes.
- [ ] `settings_category_panel.dart` is the only category-to-panel switch; nav metadata remains derived from `settings_category.dart`.
- [ ] Schedule polling starts/stops with the schedule panel and cron editor/log dialog async paths keep mounted guards.
- [ ] Existing labels, copy, cron preview, create/log/remove actions, and empty/error/loading states are unchanged.
- [ ] No file under `app/settings/` imports `WorkspaceDocument`, `WorkspaceLayoutStore`, `PaneNode`, or cockpit session classes.
- [ ] `flutter test test/settings/schedule_settings_panel_test.dart test/settings/settings_route_shell_test.dart` passes.
- [ ] `flutter analyze` passes.

## Risk
Medium — cron scheduling combines polling, dialogs, local validation, and async log loading, so the extraction must preserve mounted guards and timer disposal.

## Rollback
Move the schedule panel and cron dialogs/helpers back into `settings_page.dart`, remove `settings_category_panel.dart`, and leave Steps 1-4 intact.
