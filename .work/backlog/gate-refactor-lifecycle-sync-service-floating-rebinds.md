---
id: gate-refactor-lifecycle-sync-service-floating-rebinds
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# SyncService drops lifecycle-sensitive async rebind futures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/data/sync/sync_service.dart:305,488,521,722,727`

## Issue
Several session lifecycle operations are launched behind `// ignore: discarded_futures` without explicit `unawaited(...).catchError(...)`: pending-send failure materialization, online activation, room/session rebind, connection switch, and history replay.

## Fix
Separate truly background operations from ordering-critical rebinds; await/serialize the latter and wrap intentional fire-and-forget calls in `unawaited(...).catchError(...)` with logging and stale-session guards.
