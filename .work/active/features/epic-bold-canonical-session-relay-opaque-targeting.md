---
id: epic-bold-canonical-session-relay-opaque-targeting
kind: feature
stage: drafting
tags: [refactor, bold, relay]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-identity-model]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — relay opaque session targeting

## Brief
The relay forwards to `(to_pc, to_room)` and carries `session_id` opaquely —
it doesn't understand session semantics, just targets them. Retires
`forward_to_peer` fanout (`relay/src/peers/registry.rs:369-384`), which today
sends a cross-PC `pi_envelope` to **every** live room on the destination PC.
Absorbs the relay half of `relay-cross-pc-room-targeting`. The receiving
pi-extension broker validates the incoming `pi_envelope_in` targets a local
session/room that exists before injecting (fail-closed drop + log), alongside
the existing anti-spoof `from_pc` prefix check.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: the relay half of the contamination fix. Depends on the identity
  model pinning the relay's opaque posture.

## Foundation references
- Evidence: `relay/src/handlers/pi_forward.rs:128-173`,
  `relay/src/peers/registry.rs:369-384`, `relay/src/handlers/peer.rs:440-484`
  (normal app↔Pi outer envelopes ARE already room-targeted — the cross-PC path
  is the outlier).

<!-- /agile-workflow:refactor-design pins `to_room` on pi_envelope + the
forward path. -->
