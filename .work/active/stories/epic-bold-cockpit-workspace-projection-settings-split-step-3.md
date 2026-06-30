---
id: epic-bold-cockpit-workspace-projection-settings-split-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-settings-split
depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- `cockpit/test/settings/connectivity_settings_panel_test.dart:5`: the only added test is an import/instantiation assertion. The story acceptance criterion requires `flutter test test/settings/connectivity_settings_panel_test.dart` to pass with fake view model/gateway coverage for load, save, and controller disposal paths; this test does not exercise `ConnectivityViewModel.load`, relay save/check behavior, or pairing/revoke controller disposal.

**Verification run**:
- `cd /home/agent/forks/remote_pi && git show --stat --find-renames --find-copies da43c9d5 && git show --no-ext-diff --no-color --find-renames --find-copies da43c9d5 -- cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart cockpit/lib/app/settings/ui/settings_page.dart cockpit/test/settings/connectivity_settings_panel_test.dart .work/active/stories/epic-bold-cockpit-workspace-projection-settings-split-step-3.md`: reviewed commit `da43c9d5` diff.
- `cd /home/agent/forks/remote_pi/cockpit && flutter analyze`: failed before analysis because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp.17`, `engine.realm`).
- `cd /home/agent/forks/remote_pi/cockpit && flutter test test/settings/connectivity_settings_panel_test.dart`: failed before test execution for the same read-only Flutter cache error.

## Verification supplement (2026-06-29, env unblocked)

The env block is resolved (pub.dev reachable, `PUB_CACHE=/tmp/pi-pub-cache`, `/tmp/flutter-writable/bin/flutter`, `HOME=/tmp/pi-dart-home`). Reran the targeted commands:

- `flutter analyze` (full cockpit project) → **No issues found!** (ran in 18.4s).
- `flutter test test/settings/connectivity_settings_panel_test.dart` → **All tests passed!** but the suite contains exactly **one** test: `connectivity settings panel is importable outside settings_page`.

This confirms the bounce's blocker stands on its merits, not on the env block: the AC requires fake view-model/gateway coverage for `ConnectivityViewModel.load`, relay save/check, and pairing/revoke controller disposal, and the committed test still only proves importability. `stage: implementing` unchanged; the real test gap remains.

## Implementation notes (rework 2026-06-30)
- Files changed: `cockpit/test/settings/connectivity_settings_panel_test.dart`, `.work/active/stories/epic-bold-cockpit-workspace-projection-settings-split-step-3.md`.
- Tests added: expanded `connectivity_settings_panel_test.dart` from one import smoke test to eight tests covering `ConnectivityViewModel.load` through a fake `RelayGateway`, relay save/check behavior, `PairingController` gateway cancellation on disposal, `RevokeController` late-notification suppression after disposal, panel post-frame load/save/check wiring through a fake view model, and panel-owned pairing/revoke controller disposal after dialogs close.
- Discrepancies from design: none for the rework; production code stayed unchanged because the refactor panel already existed and the bounce only required missing test coverage.
- Adjacent issues parked: none.
- Verification:
  - `cd /home/agent/projects/remote_pi/cockpit && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && /home/agent/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline` → `Got dependencies!`.
  - `cd /home/agent/projects/remote_pi/cockpit && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && /home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze` → `No issues found! (ran in 20.3s)`.
  - `cd /home/agent/projects/remote_pi/cockpit && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && /home/agent/projects/remote_pi/.tools/flutter/bin/flutter test test/settings/connectivity_settings_panel_test.dart` → `+8: All tests passed!`.

## Review (2026-06-30)

**Verdict**: Approve

**Blockers**: none

**Important**: none

**Nits**: none

**Notes**: Reviewed rework commit `b2e3979`. The expanded `cockpit/test/settings/connectivity_settings_panel_test.dart` suite contains 8 tests and now exercises `ConnectivityViewModel.load` through a fake `RelayGateway`, relay save/check behavior through the same gateway port, `PairingController` gateway cancellation on dispose, `RevokeController` late-notification suppression after dispose, post-frame panel load/save/check wiring, and panel-owned pairing/revoke controller disposal after dialogs close. Verification run from `cockpit/`: `export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && /home/agent/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline` → `Got dependencies!`; `/home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze` → `No issues found! (ran in 19.4s)`; `/home/agent/projects/remote_pi/.tools/flutter/bin/flutter test test/settings/connectivity_settings_panel_test.dart` → `+8: All tests passed!`.
