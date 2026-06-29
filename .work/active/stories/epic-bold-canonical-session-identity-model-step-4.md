---
id: epic-bold-canonical-session-identity-model-step-4
kind: story
stage: implementing
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: [epic-bold-canonical-session-identity-model-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Preserve relay opacity and route only by peer/room

## Current State
```rust
// relay/src/protocol/outer.rs
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String,
}
```

```rust
// relay/src/peers/registry.rs
pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool {
    // cross-PC fanout to every live room of a peer
}
```

The app/Pi path already carries payload opaquely in `ct`, but legacy default-room behavior and cross-PC peer-wide fanout make room/session attribution fail open.

## Target State
```rust
// Relay routing remains session-blind.
pub struct OuterEnvelope {
    pub peer: String,
    pub room: String, // required in clean-room mode; no session_id here
    pub ct: String,   // opaque; may contain inner JSON with session_id
}

// Cross-PC targeting routes by peer + room, never by session_id.
registry.forward(to_pc, to_room, Message::Text(pi_envelope_in), EXTERNAL)
```

`session_id` stays inside endpoint-owned payloads (`ct` for app↔Pi; generic envelope body for Pi↔Pi). The relay may require explicit room/`to_room` to avoid fanout, but it never stores, parses, logs, compares, or routes by `session_id`.

## Implementation Notes
- Add relay tests that inject `session_id` inside `ct` or inside `pi_envelope.envelope.body` and prove relay output is byte/verbatim equivalent except for existing outer peer/from_pc rewrites.
- Make missing outer `room` fail closed in the clean-room path instead of defaulting to `main`; any temporary legacy parser must be isolated and marked removable.
- For cross-PC, the long-term target is `to_room`/room-addressed forwarding (owned by sibling `epic-bold-canonical-session-relay-opaque-targeting`). This story pins the invariant: the chosen cross-PC field is room targeting, not relay-learned sessions.
- Keep relay logs to peer tails, room ids, frame type names, sizes, and reasons. Never log `ct`, `session_id`, transcript, or tool args.

## Acceptance Criteria
- [ ] Relay has no `SessionId`/`session_id` domain field, registry key, database column, or routing branch.
- [ ] Relay tests prove `session_id` inside opaque payloads is carried unchanged and uninspected.
- [ ] Missing/legacy outer room handling is fail-closed or isolated behind a temporary compatibility seam with tests proving it cannot route to every active room.
- [ ] Cross-PC design notes/tests assert explicit room targeting and reject peer-wide fanout as the long-term path.
- [ ] `cargo fmt --check` and targeted relay tests pass.

## Risk
Medium. Tightening missing-room behavior is a breaking change for legacy peers; acceptable for this fork-private bold refactor, but sequence it after app/extension carry explicit rooms.

## Rollback
Restore `OuterEnvelope` default-room parsing and `forward_to_peer` usage. This reopens the known fanout risk, so only roll back together with endpoint validation if a deployment needs emergency legacy compatibility.
