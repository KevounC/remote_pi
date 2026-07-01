---
id: gate-refactor-lifecycle-dispose-leaks-active-channel
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: app-v1.2.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# ConnectionManager.dispose leaves the active transport/connect attempt unclosed

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
app/lib/data/transport/connection_manager.dart:475

## Issue
dispose() cancels timers/subscriptions and closes controllers, but does not cancel _connectCancel or close the active StatusOnline.channel. _teardownActive() does close the channel, but disposal bypasses it — disposing leaks the live WebSocket + in-flight connect attempt.

## Fix
Call _teardownActive (or cancel _connectCancel + close the active channel) during dispose, with an explicit safe fire-and-forget close path if dispose must remain synchronous.
