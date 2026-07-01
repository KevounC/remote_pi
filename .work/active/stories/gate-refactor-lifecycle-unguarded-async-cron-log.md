---
id: gate-refactor-lifecycle-unguarded-async-cron-log
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

# Cron log initial load future is discarded

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
cockpit/lib/app/settings/ui/dialogs/cron_log_dialog.dart:37

## Issue
initState calls async _load() without await, return, or unawaited.

## Fix
Needs analysis: call unawaited(_load()) and ensure _load handles thrown errors by updating _error/_loading.
