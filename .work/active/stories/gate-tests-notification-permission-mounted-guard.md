---
id: gate-tests-notification-permission-mounted-guard
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: testing
created: 2026-07-01
updated: 2026-07-01
---

# No test covers notification permission request mounted guard/instructions path

## Location
cockpit/lib/app/settings/ui/categories/notification_settings_panel.dart:76

## Issue
AC uncovered: Notification permission request still guards context use after await and still opens macOS instructions when permission is missing. (bound item: epic-bold-cockpit-workspace-projection-settings-split)

## Recommendation
Add a widget test with a fake NotificationsViewModel that completes after unmount to verify no exception, and a missing-permission case that verifies the macOS instructions dialog is opened.
