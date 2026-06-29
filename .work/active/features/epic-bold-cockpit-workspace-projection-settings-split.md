---
id: epic-bold-cockpit-workspace-projection-settings-split
kind: feature
stage: implementing
tags: [refactor, bold, cockpit]
parent: epic-bold-cockpit-workspace-projection
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Cockpit workspace — settings_page split

## Brief
`settings_page.dart` (3353 lines) is a whole settings application in one file.
Make it a route shell; each category (appearance, connectivity, daemons,
scheduling) owns its state/dialogs. The file's own `_Category` enum
(`settings_page.dart:40`) already sketches the natural seams.

## Epic context
- Parent epic: `epic-bold-cockpit-workspace-projection`
- Position: consumer of `workspace-document` (insofar as settings touches
  workspace config). Lowest-risk child; mostly mechanical split.

## Foundation references
- Evidence: `cockpit/lib/app/settings/ui/settings_page.dart:40`, `:878`,
  `:1187`, `:1717`, `:2593` (each category is already a mini-feature panel).

<!-- /agile-workflow:refactor-design pins the per-category split. -->

## Design decisions
- Treat this as a behavior-preserving settings projection refactor. The `/settings` route, visible categories, labels, dialogs, reload/polling behavior, saved preferences, relay/device operations, daemon operations, and cron operations must remain observable-equivalent.
- Resolve the workspace-document dependency by keeping the settings projection separate from `WorkspaceDocument`: workspace documents hold pane/layout/session descriptors; settings stay in their existing stores/control planes (`SettingsController`/`AppSettings` in the settings Hive box, relay config through `RelayGateway`, daemon/cron through `SupervisorClientImpl`). No settings category may import `WorkspaceLayoutStore`, `WorkspaceDocument`, or cockpit pane/session projection types.
- Use a typed settings-category registry as the single source of truth for navigation metadata and remote gating. The route shell renders that registry and delegates each category to a panel widget.
- Keep ViewModels page-scoped in `settings_module.dart`; do not introduce nested providers or widget-instantiated ViewModels. Dialog-specific controllers (`PairingController`, `RevokeController`, text controllers, timers) remain owned/disposed at their panel or dialog lifecycle boundary.
- Direct scan rationale: the target is a bounded Cockpit settings route with natural seams already marked by `_Category` and panel class boundaries in `settings_page.dart`, so Phase 3 was done by direct code reading rather than exploratory fan-out. No `.agents/skills/refactor-conventions/` or patterns catalog exists in this checkout.
- Cycle-check note: `.work/bin/work-view --blocking` is unavailable in this checkout (`No such file or directory`). I performed a manual frontmatter cycle check before emitting dependencies: no existing active item references the new `...settings-split-step-*` ids, step 1 depends only on the already-designed workspace-document feature, and later steps form a forward-only chain.

## Refactor Overview
`settings_page.dart` is currently both route shell and five mini-apps: category navigation, shared settings chrome, app preferences, language/LSP probing, notification permission state, relay pairing/revoke, daemon fleet management, and cron scheduling. The split should make settings a separate projection alongside the workspace document:

```text
SettingsPage route shell
  ├─ SettingsCategory registry/navigation (remote-gated)
  ├─ app-preferences projection: SettingsController/AppSettings + NotificationsViewModel
  ├─ connectivity projection: ConnectivityViewModel + pairing/revoke dialogs
  ├─ daemon projection: DaemonsViewModel + daemon editor dialog + polling owner
  └─ schedule projection: CronViewModel + cron editor/log dialogs + polling owner
```

The target route shell is small and declarative:

```dart
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsCategory _category = SettingsCategory.appearance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SettingsEnvGate>().check();
    });
  }

  @override
  Widget build(BuildContext context) {
    final remoteReady = context.watch<SettingsEnvGate>().remoteReady;
    final category = _category.visibleWhen(remoteReady)
        ? _category
        : SettingsCategory.appearance;
    return SettingsShell(
      selected: category,
      remoteReady: remoteReady,
      onSelect: (next) => setState(() => _category = next),
      child: SettingsCategoryPanel(category: category),
    );
  }
}
```

Category metadata is defined once:

```dart
enum SettingsCategory {
  appearance,
  languages,
  notifications,
  connectivity,
  daemons,
  scheduling;

  bool get isRemote => switch (this) {
    SettingsCategory.connectivity ||
    SettingsCategory.daemons ||
    SettingsCategory.scheduling => true,
    _ => false,
  };

  bool visibleWhen(bool remoteReady) => remoteReady || !isRemote;
}

const settingsCategoryMeta = <SettingsCategory, SettingsCategoryMeta>{
  SettingsCategory.appearance: SettingsCategoryMeta(
    label: 'Appearance',
    icon: Icons.palette_outlined,
  ),
  SettingsCategory.languages: SettingsCategoryMeta(label: 'Language', icon: Icons.code),
  SettingsCategory.notifications: SettingsCategoryMeta(
    label: 'Notifications',
    icon: Icons.notifications_outlined,
  ),
  SettingsCategory.connectivity: SettingsCategoryMeta(
    label: 'Connectivity',
    icon: Icons.wifi_tethering,
    remote: true,
  ),
  SettingsCategory.daemons: SettingsCategoryMeta(
    label: 'Daemon Agents',
    icon: Icons.dns_outlined,
    remote: true,
  ),
  SettingsCategory.scheduling: SettingsCategoryMeta(
    label: 'Schedules',
    icon: Icons.schedule_outlined,
    remote: true,
  ),
};
```

## Refactor Steps

### Step 1: Extract shared settings chrome and category registry
**Priority**: High
**Risk**: Medium
**Source Lens**: code smell / single source of truth
**Files**: `cockpit/lib/app/settings/ui/settings_page.dart`, `cockpit/lib/app/settings/ui/settings_category.dart`, `cockpit/lib/app/settings/ui/settings_shell.dart`, `cockpit/lib/app/settings/ui/widgets/settings_components.dart`
**Story**: `epic-bold-cockpit-workspace-projection-settings-split-step-1`

**Current State**:
```dart
enum _Category {
  appearance,
  languages,
  notifications,
  connectivity,
  daemons,
  scheduling,
}

class _CategoryNav extends StatelessWidget {
  const _CategoryNav({
    required this.selected,
    required this.remoteReady,
    required this.onSelect,
  });
  final _Category selected;
  final bool remoteReady;
  final ValueChanged<_Category> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      child: Column(
        children: [
          _NavItem(label: 'Appearance', selected: selected == _Category.appearance, onTap: () => onSelect(_Category.appearance), icon: Icons.palette_outlined),
          _NavItem(label: 'Language', selected: selected == _Category.languages, onTap: () => onSelect(_Category.languages), icon: Icons.code),
          // remote categories repeated inline...
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget { /* local to the god file */ }
class _Card extends StatelessWidget { /* local to the god file */ }
class _Row extends StatelessWidget { /* local to the god file */ }
class _DropdownChip extends StatelessWidget { /* local to the god file */ }
```

**Target State**:
```dart
// settings/ui/settings_category.dart
enum SettingsCategory { appearance, languages, notifications, connectivity, daemons, scheduling }

final class SettingsCategoryMeta {
  const SettingsCategoryMeta({required this.label, required this.icon, this.remote = false});
  final String label;
  final IconData icon;
  final bool remote;
}

const settingsCategoryMeta = <SettingsCategory, SettingsCategoryMeta>{/* one registry */};

extension SettingsCategoryVisibility on SettingsCategory {
  bool get isRemote => settingsCategoryMeta[this]!.remote;
  bool visibleWhen(bool remoteReady) => remoteReady || !isRemote;
}
```

```dart
// settings/ui/settings_shell.dart
class SettingsShell extends StatelessWidget {
  const SettingsShell({required this.selected, required this.remoteReady, required this.onSelect, required this.child, super.key});

  final SettingsCategory selected;
  final bool remoteReady;
  final ValueChanged<SettingsCategory> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.bg,
    child: Column(children: [
      const SettingsHeader(),
      Expanded(child: Row(children: [
        SettingsCategoryNav(selected: selected, remoteReady: remoteReady, onSelect: onSelect),
        Expanded(child: child),
      ])),
    ]),
  );
}
```

```dart
// settings/ui/widgets/settings_components.dart
class SettingsSection extends StatelessWidget { /* moved _Section unchanged */ }
class SettingsCard extends StatelessWidget { /* moved _Card unchanged */ }
class SettingsRow extends StatelessWidget { /* moved _Row unchanged */ }
class SettingsDropdownChip extends StatelessWidget { /* moved _DropdownChip unchanged */ }
class SettingsMessageCard extends StatelessWidget { /* moved _MessageCard unchanged */ }
class SettingsReloadButton extends StatelessWidget { /* moved _ReloadButton unchanged */ }
class SettingsErrorBanner extends StatelessWidget { /* moved _ErrorBanner unchanged */ }
```

**Implementation Notes**:
- Start by moving code, not changing behavior. Keep layout constants (`width: 210`, padding, title bar, labels, icons) unchanged.
- Replace `_Category` with `SettingsCategory` everywhere in `settings_page.dart` before extracting panels.
- Promote shared widgets only when used by more than one target panel. Category-local controls (`_ThemeDropdown`, `_LanguageRow`, `_DaemonTile`, `_CronTile`) move with their category in later steps.
- Keep `SettingsPage.initState` as the owner of the environment probe; route shell creation must not trigger remote shell-out before the current page does.

**Acceptance Criteria**:
- [ ] Category label/icon/remote-gating metadata lives in one registry and the nav derives from it.
- [ ] Shared settings chrome is public within the settings feature and no longer private to `settings_page.dart`.
- [ ] The visible `/settings` layout, selected-category fallback, and remote-category hiding behavior are unchanged.
- [ ] No new dependency on `WorkspaceLayoutStore`, `WorkspaceDocument`, `PaneNode`, or cockpit session classes is introduced under `app/settings/`.
- [ ] `flutter test` passes for existing cockpit tests.
- [ ] `flutter analyze` passes.

**Rollback**: Inline `settings_category.dart`, `settings_shell.dart`, and `widgets/settings_components.dart` back into `settings_page.dart`, restore `_Category`, and keep the panel bodies untouched.

---

### Step 2: Extract the app-preferences settings projection
**Priority**: High
**Risk**: Medium
**Source Lens**: code smell / ports and adapters
**Files**: `cockpit/lib/app/settings/ui/settings_page.dart`, `cockpit/lib/app/settings/ui/categories/appearance_settings_panel.dart`, `cockpit/lib/app/settings/ui/categories/language_settings_panel.dart`, `cockpit/lib/app/settings/ui/categories/notification_settings_panel.dart`, `cockpit/lib/app/settings/ui/widgets/settings_components.dart`, `cockpit/test/settings/app_preferences_settings_panel_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-settings-split-step-2`

**Current State**:
```dart
class _AppearancePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    return SingleChildScrollView(
      child: _Section(
        label: 'Theme',
        child: _Card(children: [
          _Row(
            title: 'Theme',
            trailing: _ThemeDropdown(value: s.themeMode, onChanged: controller.setThemeMode),
          ),
        ]),
      ),
    );
  }
}

class _LanguagesPanel extends StatelessWidget { /* LSP commands + probe rows */ }
class _NotificationsPanel extends StatelessWidget { /* SettingsController + NotificationsViewModel */ }
```

**Target State**:
```dart
// settings/ui/categories/appearance_settings_panel.dart
class AppearanceSettingsPanel extends StatelessWidget {
  const AppearanceSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    return SettingsPanelScroll(
      maxWidth: 680,
      child: Column(children: [
        SettingsSection(
          label: 'Theme',
          child: SettingsCard(children: [
            SettingsRow(
              title: 'Theme',
              trailing: ThemeDropdown(value: settings.themeMode, onChanged: controller.setThemeMode),
            ),
          ]),
        ),
        // fonts, syntax preview, conversation unchanged
      ]),
    );
  }
}
```

```dart
// settings/ui/categories/notification_settings_panel.dart
class NotificationSettingsPanel extends StatelessWidget {
  const NotificationSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    return SettingsPanelScroll(
      maxWidth: 680,
      child: SettingsSection(
        label: 'Notifications',
        child: SettingsCard(children: [
          SettingsRow(
            title: 'Enable notifications',
            trailing: Switch(
              value: settings.notificationsEnabled,
              onChanged: controller.setNotificationsEnabled,
            ),
          ),
          if (Platform.isMacOS && settings.notificationsEnabled)
            const NotificationPermissionRow(),
        ]),
      ),
    );
  }
}
```

**Implementation Notes**:
- Move `_AppearancePanel`, `_LanguagesPanel`, `_NotificationsPanel`, `_SyntaxPreview`, theme/syntax/font/size widgets, language-row widgets, and notification-permission row into the three category files with public class names where imported by the shell.
- Keep `SettingsController` app-scoped in `core`; panels consume it through `context.watch` exactly as today.
- Preserve `_LanguageRow` local controller ownership and `probeLspCommand` behavior; do not make LSP probing a workspace-document concern.
- Preserve notification mounted guards after async permission requests.

**Acceptance Criteria**:
- [ ] Appearance, language, and notification panels compile outside `settings_page.dart` and are imported by the route shell.
- [ ] `SettingsController` remains the only owner of `AppSettings` persistence; no panel writes Hive directly.
- [ ] LSP command probing and save/reset behavior remain covered by widget tests or an explicit smoke test.
- [ ] Notification permission request still guards `context` use after `await` and still opens macOS instructions when permission is missing.
- [ ] `flutter test test/settings/app_preferences_settings_panel_test.dart` passes.
- [ ] `flutter analyze` passes.

**Rollback**: Move the three panels and their helpers back into `settings_page.dart`, restore private names, and leave the shared shell/category extraction from Step 1 intact.

---

### Step 3: Extract the connectivity settings projection
**Priority**: High
**Risk**: Medium
**Source Lens**: code smell / lifecycle ownership
**Files**: `cockpit/lib/app/settings/ui/settings_page.dart`, `cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart`, `cockpit/lib/app/settings/ui/widgets/settings_components.dart`, `cockpit/test/settings/connectivity_settings_panel_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-settings-split-step-3`

**Current State**:
```dart
class _ConnectivityPanelState extends State<_ConnectivityPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ConnectivityViewModel>().load();
    });
  }

  Future<void> _openPairing() async {
    final vm = context.read<ConnectivityViewModel>();
    final ctrl = vm.newPairingController()..start();
    final paired = await showDialog<bool>(
      context: context,
      builder: (_) => PairingDialog(controller: ctrl),
    );
    ctrl.dispose();
    if (!mounted) return;
    if (paired == true) await vm.loadDevices();
  }
}
```

**Target State**:
```dart
class ConnectivitySettingsPanel extends StatefulWidget {
  const ConnectivitySettingsPanel({super.key});

  @override
  State<ConnectivitySettingsPanel> createState() => _ConnectivitySettingsPanelState();
}

class _ConnectivitySettingsPanelState extends State<ConnectivitySettingsPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ConnectivityViewModel>().load();
    });
  }

  Future<void> _openPairing() async {
    final vm = context.read<ConnectivityViewModel>();
    final controller = vm.newPairingController()..start();
    final paired = await showDialog<bool>(
      context: context,
      builder: (_) => PairingDialog(controller: controller),
    );
    controller.dispose();
    if (!mounted) return;
    if (paired == true) await vm.loadDevices();
  }

  @override
  Widget build(BuildContext context) => SettingsPanelScroll(
    maxWidth: 680,
    child: /* relay editor + paired devices unchanged */,
  );
}
```

**Implementation Notes**:
- Move `_ConnectivityPanel`, `_RelayEditor`, `_HealthIndicator`, `_DeviceTile`, `_PairButton`, and device helper functions together so relay/device behavior stays cohesive.
- Keep pairing and revoke dialog controllers created at the call site and disposed immediately after their dialogs close.
- Preserve `_RelayEditor` listener lifecycle: add listener in `initState`, remove listener and dispose text controller in `dispose`.
- Continue to use `ConnectivityViewModel` as the page-scoped projection; do not move relay URL into `AppSettings` in this refactor.

**Acceptance Criteria**:
- [ ] Connectivity UI compiles outside `settings_page.dart` and is imported by the route shell.
- [ ] Relay load/save/check, paired-device load/reload, pair, and revoke flows call the same `ConnectivityViewModel` methods as before.
- [ ] Pairing/revoke controllers and relay text controller/listener have explicit teardown paths.
- [ ] No connectivity code imports workspace layout/document/session classes.
- [ ] `flutter test test/settings/connectivity_settings_panel_test.dart` passes with fake view model/gateway coverage for load, save, and controller disposal paths.
- [ ] `flutter analyze` passes.

**Rollback**: Move the connectivity panel and helpers back into `settings_page.dart`, restore private names, and keep Steps 1-2 intact.

---

### Step 4: Extract the daemon settings projection
**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / lifecycle ownership
**Files**: `cockpit/lib/app/settings/ui/settings_page.dart`, `cockpit/lib/app/settings/ui/categories/daemon_settings_panel.dart`, `cockpit/lib/app/settings/ui/dialogs/daemon_editor_dialog.dart`, `cockpit/lib/app/settings/ui/widgets/settings_components.dart`, `cockpit/test/settings/daemon_settings_panel_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-settings-split-step-4`

**Current State**:
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

**Target State**:
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

**Implementation Notes**:
- Move daemon fleet UI, `_DaemonTile`, `_DaemonActionsBar`, `_FleetButton`, `_fmtUptime`, and daemon state formatting with the daemon panel.
- Extract the daemon editor dialog/result into `ui/dialogs/daemon_editor_dialog.dart`; keep its `FilePicker` use at the UI edge.
- Preserve the polling owner and cancellation in the panel state; do not move timers into the ViewModel unless a separate behavior-changing feature scopes that.
- Preserve confirmation dialogs and mounted guards after `showDialog` before calling destructive actions.

**Acceptance Criteria**:
- [ ] Daemon fleet UI and editor dialog compile outside `settings_page.dart` and are imported by the route shell/panel.
- [ ] Poll timer starts only when the daemon panel is mounted and always cancels on dispose.
- [ ] Create, rename, start/stop/restart, fleet actions, supervisor restart, and remove call the same `DaemonsViewModel` methods as before.
- [ ] `FilePicker` remains behind the daemon dialog UI edge and is not pulled into domain/ViewModel code.
- [ ] `flutter test test/settings/daemon_settings_panel_test.dart` passes with fake timers or deterministic timer cancellation coverage.
- [ ] `flutter analyze` passes.

**Rollback**: Move daemon panel/dialog code back into `settings_page.dart`, restore private names, and keep Steps 1-3 intact.

---

### Step 5: Extract the schedule settings projection and leave `SettingsPage` as a route shell
**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / missing abstraction
**Files**: `cockpit/lib/app/settings/ui/settings_page.dart`, `cockpit/lib/app/settings/ui/settings_category_panel.dart`, `cockpit/lib/app/settings/ui/categories/schedule_settings_panel.dart`, `cockpit/lib/app/settings/ui/dialogs/cron_editor_dialog.dart`, `cockpit/lib/app/settings/ui/dialogs/cron_log_dialog.dart`, `cockpit/test/settings/schedule_settings_panel_test.dart`, `cockpit/test/settings/settings_route_shell_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-settings-split-step-5`

**Current State**:
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

**Target State**:
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

**Implementation Notes**:
- Move `_AgendamentosPanel`, `_CronTile`, `_CronMeta`, cron dialogs, `_CronOptionSwitch`, `_ExampleChip`, cron formatting helpers, and cron-result view into schedule-specific files.
- Keep `CronViewModel` page-scoped in `settings_module.dart`; the schedule panel owns only UI lifecycle/timers/dialogs.
- Use `ScheduleSettingsPanel` in code, even if visible labels remain `Schedules`; avoid carrying the Portuguese `Agendamentos` class name into the split.
- Add `settings_category_panel.dart` as the one switch from registry value to panel widget. That keeps `settings_page.dart` as the route shell and makes future patchbay replacement of panels localized.

**Acceptance Criteria**:
- [ ] `settings_page.dart` contains only the route widget/state and no category panel, tile, dialog, or shared component classes.
- [ ] `settings_category_panel.dart` is the only category-to-panel switch; nav metadata remains derived from `settings_category.dart`.
- [ ] Schedule polling starts/stops with the schedule panel and cron editor/log dialog async paths keep mounted guards.
- [ ] Existing labels, copy, cron preview, create/log/remove actions, and empty/error/loading states are unchanged.
- [ ] No file under `app/settings/` imports `WorkspaceDocument`, `WorkspaceLayoutStore`, `PaneNode`, or cockpit session classes.
- [ ] `flutter test test/settings/schedule_settings_panel_test.dart test/settings/settings_route_shell_test.dart` passes.
- [ ] `flutter analyze` passes.

**Rollback**: Move the schedule panel and cron dialogs/helpers back into `settings_page.dart`, remove `settings_category_panel.dart`, and leave Steps 1-4 intact.

## Implementation Order
1. `epic-bold-cockpit-workspace-projection-settings-split-step-1` — extract shared settings shell/chrome and the category registry. Depends on `epic-bold-cockpit-workspace-projection-workspace-document` so the settings split starts only after the workspace document target is in place.
2. `epic-bold-cockpit-workspace-projection-settings-split-step-2` — extract app-preference panels (appearance, language, notifications).
3. `epic-bold-cockpit-workspace-projection-settings-split-step-3` — extract connectivity panel and preserve relay/pair/revoke lifecycles.
4. `epic-bold-cockpit-workspace-projection-settings-split-step-4` — extract daemon panel/dialogs and preserve polling/disposal.
5. `epic-bold-cockpit-workspace-projection-settings-split-step-5` — extract schedules panel/dialogs and leave `SettingsPage` as the route shell.

## Cycle check
`.work/bin/work-view --blocking` is missing from this checkout, so the mandated tool check could not run. Manual frontmatter check is linear and cycle-free:

- Step 1: `depends_on: [epic-bold-cockpit-workspace-projection-workspace-document]`
- Step 2: `depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-1]`
- Step 3: `depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-2]`
- Step 4: `depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-3]`
- Step 5: `depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-4]`

No active item references any of the new story ids before creation, and the parent feature depends only on the workspace-document feature, so no back-edge is introduced.

## Not worth doing in this feature
- Changing the persisted `AppSettings` schema or moving relay/daemon/cron state into a workspace document. That would be a behavior/schema change, not this refactor.
- Splitting `settings_module.dart` into nested feature modules. Page-scoped ViewModels already give the needed lifecycle; nested route/DI changes would add coordination risk without improving the file split.
- Reworking visible settings UX, copy, category names, polling cadence, or dialog flows. This feature is a projection split, not a redesign.
- Introducing patchbay-specific abstractions. The split keeps category projections small and portable without naming patchbay concepts in Cockpit code.
