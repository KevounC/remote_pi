---
id: epic-bold-relay-typed-actor-frame-dispatch-step-3
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-relay-typed-actor-frame-dispatch-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Route app↔Pi outer envelopes through the typed actor

**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / boundary clarity  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, generated `OuterEnvelope` type, `relay/src/protocol/outer.rs`

## Current State

Outer-envelope routing is the no-`type` fallthrough inside the same raw JSON switch that handles relay control frames:

```rust
match parse_line(&text) {
    Err(e) => warn!(peer = %peer_short, err = %e, "invalid envelope, dropping"),
    Ok(env) => {
        let ct_len = env.ct.len();
        let dest_peer = env.peer;
        let dest_room = env.room;
        let rewritten = OuterEnvelope {
            peer: peer_id.clone(),
            room: room_id.clone(),
            ct: env.ct,
        };
        let fwd_line = serde_json::to_string(&rewritten)
            .expect("OuterEnvelope serialisation is infallible");
        if !registry.forward(&dest_peer, &dest_room, Message::Text(fwd_line), conn_id) {
            warn!(from = %peer_short, dest = %dest_tail, room = %dest_room, bytes = ct_len, "dest (peer, room) not found, dropping");
        }
    }
}
```

The code is behaviorally correct but is embedded in a loop that also validates unrelated frame shapes.

## Target State

The actor receives a typed `OuterEnvelope` and owns only the app↔Pi relay rewrite/forward behavior:

```rust
impl ConnectionActor {
    async fn dispatch_outer(&mut self, env: OuterEnvelope) -> ActorDispatch {
        let ct_len = env.ct.len();
        let dest_peer = env.peer;
        let dest_room = env.room;
        let dest_tail = peer_tail(&dest_peer);

        let rewritten = OuterEnvelope {
            peer: self.peer_id.clone(),
            room: self.room_id.clone(),
            ct: env.ct,
        };

        let fwd_line = rewritten.to_json_string();
        if !self.registry.forward(&dest_peer, &dest_room, Message::Text(fwd_line), self.conn_id) {
            warn!(from = %self.peer_short, dest = %dest_tail, room = %dest_room, bytes = ct_len, "dest (peer, room) not found, dropping");
        }
        ActorDispatch::Continue
    }
}
```

The actor never decodes `ct` and never inspects app↔Pi inner chat/control bodies.

## Implementation Notes

- Keep the exact rewrite semantics: destination receives sender `peer_id`, sender `room_id`, and original `ct` verbatim.
- Preserve skip-sender behavior via `conn_id`.
- Keep the not-found warning content-free: peer tail, destination room, and byte count only.
- If generated `OuterEnvelope` has a different constructor/serializer name, wrap it behind a tiny protocol adapter; do not duplicate fields in a second hand-written struct.
- Add tests proving `ct` is carried byte-for-byte, destination `(peer, room)` is unchanged, and sender `(peer, room)` rewrite matches current behavior.

## Acceptance Criteria

- [ ] No app↔Pi outer-envelope routing logic remains in the raw socket loop.
- [ ] `ct` remains opaque and is forwarded verbatim.
- [ ] Routing remains `(dest_peer, dest_room)`, with sender rewrite to authenticated `(peer_id, room_id)`.
- [ ] Existing `OuterEnvelope` size/default-room tests still pass or have generated-type equivalents.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and targeted relay tests pass from `relay/`.

## Risk

Medium. A rewrite mistake could cause cross-room contamination or sender echo; tests must cover both.

## Rollback

Move `dispatch_outer` back into the socket loop and call the previous `parse_line`/`registry.forward` path directly.
