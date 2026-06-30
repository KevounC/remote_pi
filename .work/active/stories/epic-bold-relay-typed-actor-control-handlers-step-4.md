---
id: epic-bold-relay-typed-actor-control-handlers-step-4
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-control-handlers
depends_on: [epic-bold-relay-typed-actor-control-handlers-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Move presence and rooms control frames into typed actor handlers

**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / lifecycle ownership / missing abstraction  
**Files**: `relay/src/handlers/control.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/metrics.rs`

## Current State

The raw switch in `handle_peer` directly mutates presence/rooms subscriptions, performs backfill, rate-limits checks, dedups responses, emits metrics, and writes to the WebSocket sink:

```rust
"presence_check" => {
    let Some(peers) = parse_bounded_control_peers(&frame, t, &peer_short) else { continue; };
    let cost = control_check_cost(&peers);
    if !control_check_limiter.allow(cost) { continue; }
    let states = presence.snapshot(&peers, |p| registry.is_online(p)).await;
    let resp = serde_json::json!({ "type": "presence", "states": states }).to_string();
    if last_presence_resp.as_deref() == Some(resp.as_str()) { metrics.inc_presence_suppressed(1); }
    else { last_presence_resp = Some(resp.clone()); sink.send(Message::Text(resp)).await?; }
}

"rooms_check" => {
    for target_peer in &peers {
        let active_rooms = registry.rooms_of(target_peer);
        let resp = serde_json::json!({ "type": "rooms", "peer": target_peer, "rooms": active_rooms }).to_string();
        /* per-peer dedup + metrics */
    }
}
```

Transport, state mutation, response shaping, and dedup state are interleaved.

## Target State

The connection actor owns per-connection state and typed control handlers return actor effects:

```rust
impl ControlHandlers<'_> {
    async fn subscribe_presence(&mut self, frame: SubscribePresenceFrame) -> ActorDispatch {
        let peers = self.bounded_peers("subscribe_presence", frame.peers)?;
        self.actor.presence.subscribe(self.actor.peer_id.clone(), peers.clone()).await;
        self.actor.registry.backfill_presence(&self.actor.peer_id, &peers);
        ActorDispatch::Continue
    }

    async fn presence_check(&mut self, frame: PresenceCheckFrame) -> ActorDispatch {
        let peers = self.bounded_peers("presence_check", frame.peers)?;
        self.actor.allow_control_check(&peers)?;
        let states = self.actor.presence.snapshot(&peers, |p| self.actor.registry.is_online(p)).await;
        self.actor.emit_deduped_presence(states)
    }

    async fn rooms_check(&mut self, frame: RoomsCheckFrame) -> ActorDispatch {
        let peers = self.bounded_peers("rooms_check", frame.peers)?;
        self.actor.allow_control_check(&peers)?;
        self.actor.emit_deduped_room_snapshots(peers)
    }
}
```

`handle_peer` only sends `ActorDispatch::Send`/`SendMany` effects.

## Implementation Notes

- Preserve `subscribe_presence` backfill behavior exactly.
- Preserve `subscribe_*` replacement semantics and `unsubscribe_*` subset removal semantics.
- Preserve check cost (`peers.len().max(1)`), shared limiter window, per-connection presence dedup, per-target rooms dedup, and metrics counters.
- Keep serialized response shapes: `presence`, `rooms`, `peer_online`, `peer_offline`, `room_announced`, and `room_ended` unchanged.

## Acceptance Criteria

- [ ] Presence and rooms subscribe/unsubscribe/check behavior is implemented in typed actor handlers.
- [ ] `peer.rs` no longer directly mutates `PresenceManager` or `RoomManager` for control frames.
- [ ] Existing dedup, limiter, backfill, and metrics tests pass or are moved to the handler module.
- [ ] Malformed peer-list frames do not mutate subscriptions.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Medium. The handler extraction touches observable push/dedup behavior, especially first-response emission and subsequent suppression.

## Rollback

Move presence/rooms branches back into `handle_peer` while keeping the shared `SubscriptionIndex` if it has already landed. Because manager APIs are preserved, rollback is mechanical.

## Implementation notes
- Files changed: `relay/src/handlers/control.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, `.work/active/stories/epic-bold-relay-typed-actor-control-handlers-step-4.md`.
- Tests added: control-handler unit tests for malformed subscribe fail-closed behavior, `subscribe_presence` backfill, presence-check dedup/metrics, and rooms-check dedup/metrics; moved limiter/cost unit coverage to the connection actor module.
- Verification: from `relay/`, `cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed.
- Discrepancies from design: current generated `RelayControlFrame` variants still flatten fields into generated maps, so the handlers consume the generated enum and perform the peer-list narrowing at the handler boundary rather than taking generated per-frame peer-list structs.
- Adjacent issues parked: none.

## Review (2026-06-30, fast-lane)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 1f8544c` — only owned files: `relay/src/handlers/{control,connection_actor,peer}.rs` + this story; no stray files, no overlap with wire-discriminator's pi_forward/registry.
- `cd relay && cargo fmt --check` clean; `cargo clippy -- -D warnings` clean; `cargo test` — all binaries green (68+3+13+7+10+19 = 120 tests pass), incl. new control-handler coverage (malformed peer-list fail-closed, presence backfill, presence/rooms dedup+metrics) and moved limiter/cost unit coverage on the connection actor.
- Acceptance criteria satisfied per story (typed control handlers; presence/rooms/metrics behavior intact; public wire shapes preserved).
