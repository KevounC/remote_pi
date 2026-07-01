---
id: gate-refactor-lifecycle-queued-delivery-fire-and-forget
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

# Queued message drain discards delivery promise

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`pi-extension/src/session/sdk_session_projection.ts:502`

## Issue
`maybeDrainQueuedMessage` clears the queue and broadcasts state, then calls `void deliver(...)` even though the injected delivery callback may return a Promise; delivery failures after queue removal can be dropped.

## Fix
needs analysis
