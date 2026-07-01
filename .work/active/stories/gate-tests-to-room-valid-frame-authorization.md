---
id: gate-tests-to-room-valid-frame-authorization
kind: story
stage: implementing
tags: [testing]
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: tests
created: 2026-07-01
updated: 2026-07-01
---

# Valid to_pc/to_room frames cannot be covered because generated cross-PC DTOs omit to_room

## Severity
Critical

## Location
relay/src/protocol/generated/cross_pc.rs:20

## Issue
AC uncovered (bound item: epic-bold-canonical-session-relay-opaque-targeting):
Valid to_pc/to_room frames proceed to authorization without inspecting envelope.body.

NOTE: the underlying to_room routing appears unimplemented (PiEnvelopeFrame is
{to_pc, envelope} with no to_room; handle_pi_envelope only checks to_pc.is_empty()).
Resolving this likely requires implementing to_room parsing/routing, not just tests.

## Recommendation
Generate PiEnvelopeFrame { to_pc, to_room, envelope } and add a unit/integration test proving valid wrapper fields reach mesh authorization while body session_id remains opaque.
