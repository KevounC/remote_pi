---
id: gate-refactor-lifecycle-chat-bootstrap-floating
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

# ChatViewModel constructor discards bootstrap failures

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
`app/lib/ui/chat/viewmodels/chat_viewmodel.dart:74`

## Issue
The constructor calls async `_bootstrap()` behind `// ignore: discarded_futures`; `_bootstrap` awaits storage, connection switching, and session binding without a top-level catch, so startup failures can be dropped and race the ViewModel lifecycle.

## Fix
Launch bootstrap through an explicit unawaited wrapper that catches/logs and emits an error/no-peer state, or move bootstrap into an awaited lifecycle method owned by the caller.
