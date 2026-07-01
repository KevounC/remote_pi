---
id: gate-tests-language-lsp-probe-coverage
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

# No test covers language LSP probe/save/reset behavior

## Location
cockpit/lib/app/settings/ui/categories/language_settings_panel.dart:135

## Issue
AC uncovered: LSP command probing and save/reset behavior remain covered by widget tests or an explicit smoke test. (bound item: epic-bold-cockpit-workspace-projection-settings-split)

## Recommendation
Add a widget test for LanguageSettingsPanel that expands a language row, edits server/formatter commands, taps Save & restart, taps Reset to default, and verifies the SettingsController callbacks plus probe-state behavior.
