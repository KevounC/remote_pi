---
id: epic-bold-canonical-session-wire-discriminator-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-canonical-session-wire-discriminator
depends_on: [epic-bold-canonical-session-wire-discriminator-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Replace cross-PC peer-wide fanout with explicit room targeting while preserving relay opacity

## Current State
```rust
// relay/src/handlers/pi_forward.rs
if registry.forward_to_peer(to_pc, msg) {
    PiForwardResult::Forwarded
}

// relay/src/peers/registry.rs
pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool {
    for ((p, _), v) in lock.iter() {
        if p == peer_id { /* sends to every live room */ }
    }
}
```

This can deliver a cross-PC envelope to every live room for `to_pc`, one of the contamination vectors called out by the parent epic.

## Target State
```rust
let to_room = frame.get("to_room").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
let Some(to_room) = to_room else {
    return PiForwardResult::TransportError(make_transport_error(Some(envelope), "bad_envelope"));
};

if registry.forward_to_room(to_pc, to_room, msg) {
    PiForwardResult::Forwarded
} else {
    PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
}
```

## Implementation Notes
- `pi_envelope` adds required `to_room`; `pi_envelope_in` still carries the inner envelope verbatim plus authenticated `from_pc`.
- Relay must not inspect `session_id` in `ct` or generic envelope bodies, must not store it, and must not log it.
- Keep control-frame broadcasts (`peer_online`, `room_announced`, `room_meta_updated`) on their existing subscriber fanout paths; only cross-PC Pi envelope delivery loses peer-wide room fanout.
- `OuterEnvelope` app↔Pi room defaulting is a separate compatibility seam. For this bugfix, no-room app envelopes in `WsTransport` are dropped before app state mutation; future generated-protocol work can remove `default_room` at the schema boundary.

## Acceptance Criteria
- [ ] A `pi_envelope` missing `to_room` returns `transport_error: bad_envelope`.
- [ ] A `pi_envelope` for `to_room=room-b` reaches only room B, not every live room for `to_pc`.
- [ ] Relay tests prove `session_id` inside opaque payload/body is carried unchanged and uninspected.
- [ ] Existing presence/rooms subscriber broadcasts still fan out as before.
- [ ] `cargo fmt --check` and targeted relay tests pass.

## Risk
Medium. Existing cross-PC senders must learn `to_room`; otherwise they receive `bad_envelope`. This is intentional clean-room behavior for the fork-private bugfix.

## Rollback
Restore `forward_to_peer` use and client omission of `to_room`, knowingly re-opening the cross-room fanout vector. Do not roll back by teaching the relay to parse `session_id`.
