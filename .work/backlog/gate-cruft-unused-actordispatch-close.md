---
id: gate-cruft-unused-actordispatch-close
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

# Unused ActorDispatch::Close variant retained behind #[allow(dead_code)]

## Severity
Medium

## Location
relay/src/handlers/connection_actor.rs:28

## Issue
ActorDispatch::Close is never constructed in the relay actor pipeline, but is only kept via an explicit dead-code allow, indicating an unnecessary public enum arm and suppressed diagnostics debt.

## Recommendation
Remove the variant and peer.rs close arm if close is not yet emitted, or add a concrete production path that can actually produce it and justify the branch with a behavior-preserving reason.
