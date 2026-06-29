---
id: epic-bold-canonical-session-relay-opaque-targeting-step-4
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-canonical-session-relay-opaque-targeting
depends_on: [epic-bold-canonical-session-relay-opaque-targeting-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Lock the opaque relay boundary with regression tests and comments

## Current State

```rust
// registry.rs today exposes both targeted forward(...) and peer-wide forward_to_peer(...).
// pi_forward.rs conventionally treats envelope as verbatim, but has no room-target regression test.
```

## Target State

```rust
// Cross-PC data-plane forwarding is always room-targeted: (to_pc, to_room).
// Any session_id inside ct, room metadata, or AgentEnvelope.body is endpoint-owned opaque data.
```

## Implementation Notes

- Add a test that embeds `session_id` in `envelope.body` and proves the forwarded `pi_envelope_in.envelope` is byte/JSON-value equivalent except for relay-owned wrapper fields.
- Add a targeted-room regression test that registers two rooms under one peer and proves only `to_room` receives the frame.
- Remove stale comments that say cross-PC lacks room knowledge (`"where the relay has Pi-B's pubkey but not its room_id"`). Replace with the room-targeted invariant.
- Keep `RoomMeta.session_id` documented as opaque bootstrap metadata; it is not a routing key, lookup key, log key, or metric dimension.

## Acceptance Criteria

- [ ] Tests fail if `pi_forward` parses or branches on `session_id`.
- [ ] Comments and module docs no longer describe peer-wide fanout as the expected cross-PC path.
- [ ] `RoomMeta.session_id` remains opaque metadata and is not used by registry lookup or forwarding.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Low. This is a regression-lock and documentation cleanup step after the behavior switch.

## Rollback

Revert the tests/comments only if they block an emergency rollback to peer-wide forwarding; do not leave comments claiming room-targeted routing while fanout is restored.
