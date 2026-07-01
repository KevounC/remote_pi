---
id: gate-cruft-dynamic-setactiveroom-fallback
kind: story
stage: drafting
tags: [cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-01
---

# Silent dynamic transport fallback for setActiveRoom

## Severity
Low

## Location
app/lib/data/transport/connection_manager.dart:272

## Issue
_propagateActiveRoom uses dynamic to call setActiveRoom and swallows all errors in a blanket catch. A transport/API mismatch can be hidden, silently falling back to implicit default room behavior.

## Recommendation
Add setActiveRoom to the transport contract (or a tiny capability interface), catch only expected unsupported cases, and log unexpected failures so regressions are observable.
