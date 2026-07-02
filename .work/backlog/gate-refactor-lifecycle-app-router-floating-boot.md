---
id: gate-refactor-lifecycle-app-router-floating-boot
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

# App router starts ConnectionManager.boot as an unguarded future

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/routing/app_router.dart:119`

## Issue
`AppRouter.load` suppresses the unawaited-future lint and calls `conn.boot(preferredEpk: selected)` without awaiting, returning, `unawaited(...)`, or attaching error handling.

## Fix
Decide whether boot must complete before routing continues; either await it in the bootstrap flow or wrap it in `unawaited(conn.boot(...).catchError(...))` with explicit logging/recovery semantics.
