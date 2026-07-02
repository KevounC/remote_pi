---
id: epic-bold-relay-typed-actor-registry-split-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-frame-dispatch, epic-bold-relay-typed-actor-control-handlers]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 1: Extract the connection table and delivery adapter

## Current State

```rust
type RoomKey = (String, String);
type ConnEntry = (u64, RoomMeta, mpsc::UnboundedSender<Message>);

pub struct PeerRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnEntry>>>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}
```

`PeerRegistry` directly owns connection IDs, live senders, per-connection room metadata, delivery helpers, and lifecycle booleans.

## Target State

```rust
pub(crate) type RoomKey = (String, String);

pub(crate) struct ConnectionEntry {
    pub conn_id: u64,
    pub room_meta: RoomMeta,
    pub tx: mpsc::UnboundedSender<Message>,
}

pub(crate) struct ConnectionRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnectionEntry>>>,
}
```

`PeerRegistry` remains the public facade for this step, delegating sender-map operations to `ConnectionRegistry`.

## Implementation Notes

- Add `relay/src/peers/connections.rs` and export it from `peers/mod.rs`.
- Preserve current APIs: `register`, `unregister`, `forward`, `forward_to_peer`, `rooms_of`, `backfill_presence`, and `update_room_meta` still compile through `PeerRegistry`.
- Return explicit mutation facts from connection insert/remove (`was_offline_before`, `is_first_in_room`, `room_emptied`, `peer_offlined`) rather than rescanning in the facade.
- Keep `room_meta` in `ConnectionEntry` for this story only; step 2 removes it.
- If canonical-session has already removed peer-wide `forward_to_peer`, re-home the replacement delivery API instead of reintroducing fanout.

## Acceptance Criteria

- [ ] `next_conn` and `senders` live in `ConnectionRegistry`, not directly in `PeerRegistry`.
- [ ] Existing call sites compile without behavior changes.
- [ ] Duplicate room, skip-sender, stale unregister, and cross-PC delivery tests still pass.
- [ ] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Implementation

- Extracted `ConnectionRegistry` and `ConnectionEntry` into `relay/src/peers/connections.rs`; `next_conn` and `senders` now live there instead of directly in `PeerRegistry`.
- Kept `PeerRegistry` as the public facade. Existing `register`, `unregister`, `forward`, `forward_to_peer`, `forward_to_room`, `rooms_of`, `backfill_presence`, and `update_room_meta` delegate sender-table and delivery operations through `ConnectionRegistry`.
- `ConnectionRegistry::insert` / `remove` return explicit mutation facts (`was_offline_before`, `is_first_in_room`, `room_emptied`, `peer_offlined`) so the facade publishes the same lifecycle events without rescanning for those transitions.
- Preserved step-1 compatibility by keeping `room_meta` on each `ConnectionEntry`; room metadata store extraction remains for the next story.
- Tests added: none; existing registry, presence, rooms, integration, and cross-PC forwarding coverage remained the refactor proof.
- Verification: `cargo fmt --check`, `cargo clippy -- -D warnings`, `cargo test` (148 tests), and `cargo build` passed from `relay/`.
- Discrepancies from design: none.

## Risk

Medium. The sender map is hot path connection state; mistakes can break routing or disconnect cleanup even though the intended change is mechanical.

## Rollback

Inline `ConnectionRegistry` back into `PeerRegistry` and restore the tuple `ConnEntry` map. No wire behavior or persisted state changes are involved.

## Review

Approved (2026-06-30). Independently re-ran: relay `cargo fmt --check` clean;
`cargo clippy -- -D warnings` clean; `cargo test` 148 passed / 0 failed (pure
refactor — existing registry/presence/rooms/integration/cross-PC coverage is
the proof). Commit `a75b0f6` scoped to peers/connections.rs (new) + peers/mod.rs
+ peers/registry.rs + story .md; relay-only, no generated files.

`ConnectionRegistry` + `ConnectionEntry` extracted to connections.rs (next_conn
+ senders map); `PeerRegistry` remains the public facade — all APIs preserved
(register/unregister/forward/forward_to_peer/forward_to_room/rooms_of/
backfill_presence/update_room_meta delegate through ConnectionRegistry). The
insert/remove mutation-facts design (was_offline_before/is_first_in_room/
room_emptied/peer_offlined) lets the facade publish lifecycle events without
rescanning — clean separation. room_meta stays on ConnectionEntry for now
(room metadata store extraction deferred to next story, as noted).
