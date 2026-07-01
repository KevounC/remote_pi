---
id: gate-tests-pi-envelope-in-to-room
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

# Successful pi_envelope_in delivery does not test required to_room metadata

## Severity
Critical

## Location
relay/src/handlers/pi_forward.rs:181

## Issue
AC uncovered (bound item: epic-bold-canonical-session-relay-opaque-targeting):
Successful pi_envelope delivery emits pi_envelope_in with from_pc, to_room, and verbatim envelope. Current tests assert to_room is absent at pi_forward_test.rs:158, :221, :258.

NOTE: the underlying to_room routing appears unimplemented (PiEnvelopeFrame is
{to_pc, envelope} with no to_room; handle_pi_envelope only checks to_pc.is_empty()).
Resolving this likely requires implementing to_room parsing/routing, not just tests.

## Recommendation
Add happy-path assertions that pi_envelope_in.to_room equals the requested room and the envelope is unchanged.
