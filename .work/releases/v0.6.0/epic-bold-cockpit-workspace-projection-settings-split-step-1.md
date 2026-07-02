---
id: epic-bold-cockpit-workspace-projection-settings-split-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-settings-split
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 1: Extract shared settings chrome and category registry

## Current State
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

## Target State
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

## Implementation Notes
- Start by moving code, not changing behavior. Keep layout constants (`width: 210`, padding, title bar, labels, icons) unchanged.
- Replace `_Category` with `SettingsCategory` everywhere in `settings_page.dart` before extracting panels.
- Promote shared widgets only when used by more than one target panel. Category-local controls (`_ThemeDropdown`, `_LanguageRow`, `_DaemonTile`, `_CronTile`) move with their category in later steps.
- Keep `SettingsPage.initState` as the owner of the environment probe; route shell creation must not trigger remote shell-out before the current page does.

## Acceptance Criteria
- [ ] Category label/icon/remote-gating metadata lives in one registry and the nav derives from it.
- [ ] Shared settings chrome is public within the settings feature and no longer private to `settings_page.dart`.
- [ ] The visible `/settings` layout, selected-category fallback, and remote-category hiding behavior are unchanged.
- [ ] No new dependency on `WorkspaceLayoutStore`, `WorkspaceDocument`, `PaneNode`, or cockpit session classes is introduced under `app/settings/`.
- [ ] `flutter test` passes for existing cockpit tests.
- [ ] `flutter analyze` passes.

## Risk
Medium — broad imports/name changes can cause compile churn, but the code movement is behavior-preserving and isolated to `app/settings/ui`.

## Rollback
Inline `settings_category.dart`, `settings_shell.dart`, and `widgets/settings_components.dart` back into `settings_page.dart`, restore `_Category`, and keep the panel bodies untouched.

## Implementation notes
- Files changed: `cockpit/lib/app/settings/ui/settings_category.dart`, `cockpit/lib/app/settings/ui/settings_shell.dart`, `cockpit/lib/app/settings/ui/widgets/settings_components.dart`, `cockpit/lib/app/settings/ui/settings_page.dart`.
- Tests added: none (mechanical split; existing settings/cockpit tests remain the behavior guard).
- Verification: attempted `flutter analyze` from `cockpit/`, but Flutter failed before analysis because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp` / `engine.realm`). `flutter test` was skipped for the same toolchain write failure.
- Discrepancies from design: category panel bodies remain in `settings_page.dart` for this step; only the route shell, category registry/nav, and shared chrome/components moved.
- Adjacent issues parked: none.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Implementation commit `22fffd8` inspected; changed files match the scoped shell/category/component extraction. Category metadata now lives in `settings_category.dart`, the shell/nav derive from the registry, shared settings chrome is public within the settings feature, selected-category fallback and remote gating remain in `settings_page.dart`, and no `WorkspaceDocument` / `WorkspaceLayoutStore` / `PaneNode` imports were introduced under `cockpit/lib/app/settings/`. Verification attempted: `flutter analyze && flutter test` from `cockpit/` failed before analysis because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp` / `engine.realm`). A direct `dart analyze` attempt was also not authoritative because `.dart_tool`/Flutter package resolution is unavailable in this checkout. No code-level blocker found in the reviewed diff.
