---
id: gate-refactor-lifecycle-session-start-fire-and-forget
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

# Session start auto-start future is discarded without error handling

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`pi-extension/src/extension/composition_root.ts:58`

## Issue
The `session_start` hook calls `void ports.commands.ensureStarted?.(ctx)`; if the async auto-start path rejects, the failure is not awaited or caught by the lifecycle hook.

## Fix
needs analysis
