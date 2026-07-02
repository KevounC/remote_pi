---
id: gate-refactor-lifecycle-connection-retry-floating
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

# Connection retry timer discards the reconnect future

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/data/transport/connection_manager.dart:1190`

## Issue
The retry `Timer` callback calls async `_connect(peer)` without awaiting, returning, `unawaited(...)`, or attaching a catch, so reconnect ordering and unexpected errors are not explicitly owned by the timer lifecycle.

## Fix
Make the fire-and-forget intent explicit with `unawaited(_connect(peer).catchError(...))`, or route retries through an awaited/serialized reconnect loop that owns cancellation and error reporting.
