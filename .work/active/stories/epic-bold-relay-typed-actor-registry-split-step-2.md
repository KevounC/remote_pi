---
id: epic-bold-relay-typed-actor-registry-split-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-1]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
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

- [x] One canonical `RoomMeta` exists per live `(peer, room)`.
- [x] `rooms_of` and `update_room_meta` use the room-state store, not connection entries.
- [x] Tests cover duplicate connection metadata compatibility, first/last room events, and `working` true/false/absent patches.
- [x] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Risk

High. `RoomMetaPatch.working` drives remote working-state convergence, and duplicate room metadata currently has subtle `v.last()` behavior.

## Rollback

Restore `RoomMeta` to connection entries and move `rooms_of`/`update_room_meta` back to the sender map. This is a pure code revert because the wire shape is unchanged.

## Implementation

- Added `relay/src/peers/rooms.rs` with `RoomStateStore`, a mutex-protected canonical map keyed by `(peer_id, room_id)`.
- `ConnectionEntry` now stores only `conn_id` and sender; room metadata is no longer duplicated across live connection entries.
- `PeerRegistry::rooms_of` and `PeerRegistry::update_room_meta` read/write the room-state store. Duplicate connections refresh the canonical rooms snapshot while suppressing duplicate `room_announced`; `room_ended` still emits only when the last connection leaves.
- Preserved `RoomMetaPatch` merge semantics: nullable string fields set/clear, absent fields preserve prior state, and `working: true` / `working: false` both publish explicit convergence state while omitted `working` preserves the current value. `session_id` remains opaque metadata only.
- Added focused tests for room store canonicalization plus registry-level duplicate metadata compatibility / first-last event behavior. Full relay verification passed: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build` (97 lib tests, 3 integration tests, 13 mesh tests, 8 pi-forward tests, 10 presence tests, 2 protocol parity tests, 19 rooms tests, doc-tests 0).

## Review

Approved (2026-06-30) with HIGH-risk convergence verification. Independently
re-ran: relay `cargo fmt --check` clean; `cargo clippy -- -D warnings` clean;
`cargo test` 152 passed / 0 failed (97 lib + 3 integ + 13 mesh + 8 pi_forward +
10 presence + 2 parity + 19 rooms; +4 new room-state tests). Commit `4c1abd1`
scoped to peers/rooms.rs (new RoomStateStore) + connections.rs + registry.rs +
mod.rs + story .md; relay-only, no generated files.

Canonical room metadata verified: `RoomStateStore` (mutex-protected map keyed
by `(peer_id, room_id)`) is the single source of truth; `ConnectionEntry` now
stores only `conn_id` + sender (no duplicated `RoomMeta`); `rooms_of`/
`update_room_meta` read/write the store. Convergence invariants verified directly
in tests: duplicate-connection-refreshes-snapshot-without-duplicate-`room_announced`;
`room_ended` only on last disconnect; `working` tri-state (true publishes true,
false publishes false, absent preserves prior — `patch_preserves_working_absence
_and_applies_false`); nullable string clears; `session_id` opaque metadata only.
The subtle `v.last()` behavior is correctly reproduced by the canonical store.
