---
id: epic-bold-relay-typed-actor-registry-split-step-2
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Move room lifecycle and metadata into a room-state store

## Current State

```rust
pub fn rooms_of(&self, peer_id: &str) -> Vec<RoomMeta> {
    let lock = self.senders.lock().unwrap();
    let mut by_room: HashMap<String, RoomMeta> = HashMap::new();
    for ((p, _), v) in lock.iter() {
        if p == peer_id && let Some((_, meta, _)) = v.last() {
            by_room.insert(meta.room_id.clone(), meta.clone());
        }
    }
    by_room.into_values().collect()
}
```

Room metadata is duplicated in every connection entry and `update_room_meta` mutates every copy before broadcasting.

## Target State

```rust
pub(crate) struct RoomStateStore {
    rooms: Mutex<HashMap<RoomKey, RoomMeta>>,
}

impl RoomStateStore {
    pub fn on_connection_inserted(&self, peer_id: &str, meta: RoomMeta, insert: &ConnectionInsert) -> Option<RoomMeta>;
    pub fn on_connection_removed(&self, peer_id: &str, room_id: &str, remove: &ConnectionRemove) -> Option<RoomEnded>;
    pub fn rooms_of(&self, peer_id: &str) -> Vec<RoomMeta>;
    pub fn apply_patch(&self, peer_id: &str, room_id: &str, patch: RoomMetaPatch) -> Option<RoomMetaPatchResult>;
}
```

There is one canonical room metadata snapshot per live `(peer, room)`.

## Implementation Notes

- Place the store under `relay/src/peers/rooms.rs` or a submodule under `relay/src/rooms/` if implementation has already split room code.
- Remove `RoomMeta` from `ConnectionEntry` once room state is authoritative.
- Preserve duplicate-connection compatibility: a later connection for the same `(peer, room)` can refresh the `rooms_check` snapshot but must not emit a second `room_announced`.
- Preserve first-connection `room_announced`, last-connection `room_ended`, nullable string clears, and `working` absent/true/false semantics.
- Keep `session_id` opaque; store and publish it, but do not route or authorize by it.

## Acceptance Criteria

- [ ] One canonical `RoomMeta` exists per live `(peer, room)`.
- [ ] `rooms_of` and `update_room_meta` use the room-state store, not connection entries.
- [ ] Tests cover duplicate connection metadata compatibility, first/last room events, and `working` true/false/absent patches.
- [ ] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Risk

High. `RoomMetaPatch.working` drives remote working-state convergence, and duplicate room metadata currently has subtle `v.last()` behavior.

## Rollback

Restore `RoomMeta` to connection entries and move `rooms_of`/`update_room_meta` back to the sender map. This is a pure code revert because the wire shape is unchanged.
