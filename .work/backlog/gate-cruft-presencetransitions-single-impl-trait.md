---
id: gate-cruft-presencetransitions-single-impl-trait
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

# PresenceTransitions is a single-impl, pass-through trait

## Severity
Low

## Location
relay/src/peers/registry.rs:64

## Issue
The PresenceTransitions trait has one implementation (PresenceState) and only delegates to already-defined functions, adding no polymorphic behavior and extra indirection.

## Recommendation
Remove the trait/impl indirection and call PresenceState transition logic directly (or convert to direct inherent methods), which reduces surface area and avoids unused abstraction debt.
