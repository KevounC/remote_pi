---
id: epic-bold-cockpit-workspace-projection-settings-split-step-2
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-settings-split
depends_on: [epic-bold-cockpit-workspace-projection-settings-split-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Extract the app-preferences settings projection

## Current State
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

## Target State
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

## Implementation Notes
- Move `_AppearancePanel`, `_LanguagesPanel`, `_NotificationsPanel`, `_SyntaxPreview`, theme/syntax/font/size widgets, language-row widgets, and notification-permission row into the three category files with public class names where imported by the shell.
- Keep `SettingsController` app-scoped in `core`; panels consume it through `context.watch` exactly as today.
- Preserve `_LanguageRow` local controller ownership and `probeLspCommand` behavior; do not make LSP probing a workspace-document concern.
- Preserve notification mounted guards after async permission requests.

## Acceptance Criteria
- [ ] Appearance, language, and notification panels compile outside `settings_page.dart` and are imported by the route shell.
- [ ] `SettingsController` remains the only owner of `AppSettings` persistence; no panel writes Hive directly.
- [ ] LSP command probing and save/reset behavior remain covered by widget tests or an explicit smoke test.
- [ ] Notification permission request still guards `context` use after `await` and still opens macOS instructions when permission is missing.
- [ ] `flutter test test/settings/app_preferences_settings_panel_test.dart` passes.
- [ ] `flutter analyze` passes.

## Risk
Medium — LSP probing and notification permission paths include async UI code, so the move must preserve mounted guards and controller disposal exactly.

## Rollback
Move the three panels and their helpers back into `settings_page.dart`, restore private names, and leave the shared shell/category extraction from Step 1 intact.
