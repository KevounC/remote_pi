---
id: gate-refactor-lifecycle-room-persist-fire-and-forget
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

# Room persistence writes are fire-and-forget without error handling

## Library
lifecycle

## Rule
unguarded-async-void

## Confidence
Medium

## Location
app/lib/data/transport/connection_manager.dart:661

## Issue
_persistRoomsForPeer(key) is called from control-frame handling with only a lint ignore; similar calls at 732, 782, 923, 935, 971. Storage failures dropped, writes can outlive teardown.

## Fix
needs analysis
