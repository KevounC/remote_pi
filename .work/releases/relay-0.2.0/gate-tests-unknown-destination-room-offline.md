---
id: gate-tests-unknown-destination-room-offline
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

# Unknown destination room is not covered as correlated offline

## Severity
Critical

## Location
relay/src/handlers/pi_forward.rs:186

## Issue
AC uncovered (bound item: epic-bold-canonical-session-relay-opaque-targeting):
Unknown destination room returns transport_error: offline correlated to the original envelope id.

NOTE: the underlying to_room routing appears unimplemented (PiEnvelopeFrame is
{to_pc, envelope} with no to_room; handle_pi_envelope only checks to_pc.is_empty()).
Resolving this likely requires implementing to_room parsing/routing, not just tests.

## Recommendation
Add an integration test where the destination peer is online in one room, the sender targets a different to_room, and the sender receives _relay transport_error: offline with re set to the original id.
