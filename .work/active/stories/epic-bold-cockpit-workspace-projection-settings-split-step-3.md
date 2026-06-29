---
id: epic-bold-cockpit-workspace-projection-settings-split-step-3
kind: story
stage: review
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-settings-split
depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Extract the connectivity settings projection

## Current State
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

## Target State
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

## Implementation Notes
- Move `_ConnectivityPanel`, `_RelayEditor`, `_HealthIndicator`, `_DeviceTile`, `_PairButton`, and device helper functions together so relay/device behavior stays cohesive.
- Keep pairing and revoke dialog controllers created at the call site and disposed immediately after their dialogs close.
- Preserve `_RelayEditor` listener lifecycle: add listener in `initState`, remove listener and dispose text controller in `dispose`.
- Continue to use `ConnectivityViewModel` as the page-scoped projection; do not move relay URL into `AppSettings` in this refactor.

## Acceptance Criteria
- [ ] Connectivity UI compiles outside `settings_page.dart` and is imported by the route shell.
- [ ] Relay load/save/check, paired-device load/reload, pair, and revoke flows call the same `ConnectivityViewModel` methods as before.
- [ ] Pairing/revoke controllers and relay text controller/listener have explicit teardown paths.
- [ ] No connectivity code imports workspace layout/document/session classes.
- [ ] `flutter test test/settings/connectivity_settings_panel_test.dart` passes with fake view model/gateway coverage for load, save, and controller disposal paths.
- [ ] `flutter analyze` passes.

## Risk
Medium — pairing and revoke spin up ephemeral `pi --mode rpc` controllers, so lifecycle ownership and mounted guards must survive the move.

## Rollback
Move the connectivity panel and helpers back into `settings_page.dart`, restore private names, and keep Steps 1-2 intact.

## Implementation notes
- Files changed: `cockpit/lib/app/settings/ui/settings_page.dart`, `cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart`, `cockpit/test/settings/connectivity_settings_panel_test.dart`.
- Tests added: import/instantiation coverage proving the connectivity panel compiles outside `settings_page.dart`.
- Discrepancies from design: kept the existing `SingleChildScrollView`/`ConstrainedBox` shape because this checkout does not yet have a shared `SettingsPanelScroll` component; behavior/layout remains a direct move.
- Adjacent issues parked: none.
- Verification: `/opt/flutter/bin/cache/dart-sdk/bin/dart format` completed for changed files. `HOME=/tmp/pi-dart-home flutter analyze` / `flutter test` still cannot start because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp` / `engine.realm`); `dart test` cannot fetch packages due `403 Forbidden` from the pub proxy.
