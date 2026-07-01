---
id: gate-tests-to-room-missing-bad-envelope
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

# Missing/empty to_room is not tested as bad_envelope

## Severity
Critical

## Location
relay/src/handlers/pi_forward.rs:167

## Issue
AC uncovered (bound item: epic-bold-canonical-session-relay-opaque-targeting):
pi_envelope with missing/empty to_room returns bad_envelope in the clean-room path. Current coverage asserts the opposite (to_room absent) at pi_forward_test.rs:353.

NOTE: the underlying to_room routing appears unimplemented (PiEnvelopeFrame is
{to_pc, envelope} with no to_room; handle_pi_envelope only checks to_pc.is_empty()).
Resolving this likely requires implementing to_room parsing/routing, not just tests.

## Recommendation
Add to_room to the cross-PC frame type and tests for missing and empty to_room returning transport_error: bad_envelope.
