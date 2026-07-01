---
id: gate-refactor-lifecycle-unguarded-async-language-settings
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# LSP probe future is fired without explicit handling

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/language_settings_panel.dart:112,151,161

## Issue
_detect() is async but is called from sync paths without await/unawaited.

## Fix
Needs analysis: wrap probe calls in unawaited(_detect()) and make _detect catch/report probe errors deterministically.
