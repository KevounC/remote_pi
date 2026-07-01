---
id: epic-bold-relay-typed-actor-frame-dispatch-step-3
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-relay-typed-actor-frame-dispatch-step-2]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation

- Routed `DecodedRelayFrame::Outer` through `ConnectionActor::dispatch_outer`; `relay/src/handlers/peer.rs` remains a raw socket/lifecycle loop with no app↔Pi outer-envelope rewrite/forward logic.
- Added a tiny `OuterEnvelope::to_json_string()` adapter in `relay/src/protocol/outer.rs` so forwarding serializes the generated type without a second handwritten struct; no generator or generated files were changed.
- Preserved `ct` opacity and verbatim forwarding: the actor only measures `ct.len()` for the content-free not-found warning, never decodes or inspects app↔Pi inner bodies.
- Preserved rewrite semantics: route lookup stays `(dest_peer, dest_room)`, while the delivered envelope carries authenticated sender `peer_id`, sender `room_id`, and original `ct`.
- Preserved sender-skip behavior by forwarding with the actor's `conn_id`.
- Added actor tests proving byte-for-byte `ct` carry, sender peer/room rewrite, exact destination room routing with no sibling-room contamination, and skip-sender/no sender echo while another same-key connection still receives.
- Regen verdict: not applicable; generator and generated protocol files were untouched.
- Verification: `cargo test dispatch_outer --lib` passed (3/3 targeted tests). Full relay verification passed: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build`; `cargo test` reported 85 lib tests, 0 main tests, and integration suites 3 + 13 + 8 + 10 + 2 + 19 all passing.

## Review

Approved (2026-06-30). Independently re-ran: relay `cargo fmt --check` clean;
`cargo clippy -- -D warnings` clean; `cargo test` 140 passed / 0 failed (85 lib +
3 integ + 13 mesh + 8 pi_forward + 10 presence + 2 parity + 19 rooms; +3 new
dispatch_outer tests). Commit `5231213` scoped to connection_actor.rs + outer.rs
(tiny `to_json_string()` adapter — no second handwritten struct) + story .md;
relay-only, no generated files touched (regen N/A).

ct-opacity + rewrite-semantics invariants verified directly via 3 descriptively-
named tests: `dispatch_outer_forwards_ct_verbatim_and_rewrites_sender_identity`
(byte-for-byte ct + sender peer_id/room_id rewrite), `dispatch_outer_targets_
exact_destination_room_without_cross_room_contamination` (cross-room containment),
`dispatch_outer_skips_sender_connection_without_suppressing_other_matching_connections`
(skip-sender via conn_id, no sender echo). No outer-envelope routing remains in the
socket loop.
