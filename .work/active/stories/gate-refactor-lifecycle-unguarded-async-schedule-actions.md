---
id: gate-refactor-lifecycle-unguarded-async-schedule-actions
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

# Schedule action buttons discard Future-returning callbacks

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/categories/schedule_settings_panel.dart:137,330

## Issue
Future-returning schedule actions are invoked from sync UI callbacks without explicit handling.

## Fix
Needs analysis: use unawaited(...) with callee-side error reporting, or introduce a shared async action runner.
