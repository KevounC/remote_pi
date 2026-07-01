---
id: gate-tests-daemon-create-flow
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

# Daemon tests cover rename/cancel but not successful create flow

## Location
cockpit/lib/app/settings/ui/categories/daemon_settings_panel.dart:40

## Issue
AC uncovered: Create, rename, start/stop/restart, fleet actions, supervisor restart, and remove call the same DaemonsViewModel methods as before. (bound item: epic-bold-cockpit-workspace-projection-settings-split)

## Recommendation
Add a successful create-path test for DaemonSettingsPanel/DaemonEditorDialog that supplies a chosen folder and asserts DaemonsViewModel.create(cwd, name: ...) is called.
