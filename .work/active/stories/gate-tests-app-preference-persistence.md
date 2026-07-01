---
id: gate-tests-app-preference-persistence
kind: story
stage: drafting
tags: [testing]
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: testing
created: 2026-07-01
updated: 2026-07-01
---

# App-preference panels only have importability coverage, not persistence/controller behavior

## Location
cockpit/lib/app/settings/ui/categories/appearance_settings_panel.dart:16

## Issue
AC uncovered: SettingsController remains the only owner of AppSettings persistence; no panel writes Hive directly. (bound item: epic-bold-cockpit-workspace-projection-settings-split)

## Recommendation
Strengthen test/settings/app_preferences_settings_panel_test.dart to pump appearance/language/notification panels with a memory SettingsStore, interact with controls, and assert settings are saved through SettingsController.
