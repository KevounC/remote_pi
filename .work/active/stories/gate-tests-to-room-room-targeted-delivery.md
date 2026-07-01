---
id: gate-tests-to-room-room-targeted-delivery
kind: story
stage: done
tags: [testing]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: tests
created: 2026-07-01
updated: 2026-07-01
---

# Cross-PC forwarding is still covered as peer-wide fanout, not room-targeted delivery

## Severity
Critical

## Location
relay/src/handlers/pi_forward.rs:186

## Issue
AC uncovered (bound item: epic-bold-canonical-session-relay-opaque-targeting):
Tests prove two live rooms for the same destination peer receive only the addressed room. Current tests assert peer-wide delivery at pi_forward_test.rs:229.

NOTE: the underlying to_room routing appears unimplemented (PiEnvelopeFrame is
{to_pc, envelope} with no to_room; handle_pi_envelope only checks to_pc.is_empty()).
Resolving this likely requires implementing to_room parsing/routing, not just tests.

## Recommendation
Replace peer-wide coverage with a regression: connect destination rooms main and work, send to_room: work, assert only work receives the frame.
