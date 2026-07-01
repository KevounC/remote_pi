---
id: gate-refactor-lifecycle-unguarded-async-daemon-actions
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

# Daemon action buttons discard Future-returning callbacks

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/daemon_settings_panel.dart:299,354,486

## Issue
Future-returning daemon actions are invoked from sync button callbacks without explicit unawaited or error handling at the callsite.

## Fix
Needs analysis: use unawaited(...) with callee-side error reporting, or introduce a shared async action runner.
