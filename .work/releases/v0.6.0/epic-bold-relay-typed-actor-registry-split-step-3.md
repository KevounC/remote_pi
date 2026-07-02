---
id: epic-bold-relay-typed-actor-registry-split-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-2]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 3: Make presence transitions an explicit actor-owned state boundary

## Current State

```rust
let was_offline_before = !lock.keys().any(|(p, _)| p == &peer_id);
/* insert */
if was_offline_before { /* emit peer_online */ }

let peer_offlined = room_emptied && !lock.keys().any(|(p, _)| p == peer_id);
if peer_offlined {
    self.presence.record_offline(peer_id, now_ms).await;
    self.presence.unsubscribe_all(peer_id).await;
}
```

Online/offline transitions are implicit booleans in `PeerRegistry` methods and are mixed with event publication.

## Target State

```rust
pub(crate) enum PresenceTransition {
    BecameOnline { peer_id: String },
    StayedOnline { peer_id: String },
    BecameOffline { peer_id: String, since_ts: i64 },
    StayedOnlineAfterDisconnect { peer_id: String },
}

pub(crate) struct PresenceState;

impl PresenceState {
    pub fn on_connection_inserted(insert: &ConnectionInsert) -> PresenceTransition;
    pub fn on_connection_removed(remove: &ConnectionRemove, now_ms: i64) -> Option<PresenceTransition>;
}
```

Presence transition calculation is named, testable, and separate from subscription storage and delivery.

## Implementation Notes

- Use facts returned by `ConnectionRegistry`; do not create a second drifting online source.
- `PresenceManager` may keep subscriptions and `last_offline_ts`; this story extracts transition calculation and cleanup orchestration from the grab-bag registry.
- Preserve no duplicate `peer_online` on multi-device reconnects and no premature `peer_offline` while another room/connection remains live.
- Keep `PresenceManager::snapshot` observable behavior unchanged.

## Acceptance Criteria

- [x] Presence transition calculation is outside the registry facade and has targeted tests.
- [x] `is_online` still uses the connection-state source of truth.
- [x] `peer_online` emitted/suppressed metrics remain unchanged for duplicate connection cases.
- [x] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Risk

Medium. Presence events are deduped by edge transitions; a bad split can create notification firehose or hide real offline transitions.

## Rollback

Move transition booleans back into `PeerRegistry::register` and `PeerRegistry::unregister`, keeping earlier connection/room modules if they are stable.

## Implementation

- Added `relay/src/peers/presence_state.rs` with `PresenceState` and explicit `PresenceTransition` variants for `BecameOnline`, `StayedOnline`, `BecameOffline`, and `StayedOnlineAfterDisconnect`.
- `PeerRegistry::register` and `PeerRegistry::unregister` now call `PresenceState` using `ConnectionRegistry` mutation facts instead of reading implicit presence booleans inline. `is_online` remains delegated to `ConnectionRegistry`, keeping the live connection table as the source of truth.
- Extended `ConnectionInsert` / `ConnectionRemove` facts with the affected `peer_id` and a `removed_connection` no-op guard so the target transition functions can be pure and testable without maintaining a second online table.
- Preserved duplicate-online behavior and metrics: duplicate connection cases still suppress extra `peer_online` and increment the suppressed counter; first online transition increments emitted. Added registry coverage for multi-room disconnects so `peer_offline` waits until the final live room/connection is gone.
- `PresenceManager` remains responsible for subscriptions and `last_offline_ts`; `PresenceManager::snapshot` behavior is unchanged.
- Verification passed from `relay/`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build`. Test counts: 103 lib tests (including 5 new `PresenceState` unit tests and 1 new registry multi-room offline test), 3 integration tests, 13 mesh tests, 8 pi-forward tests, 10 presence tests, 2 protocol parity tests, 19 rooms tests, and 0 doc-tests.

## Review

Approved (2026-06-30). Independently re-ran: relay `cargo fmt --check` clean;
`cargo clippy -- -D warnings` clean; `cargo test` 158 passed / 0 failed (103 lib
incl. 5 new PresenceState unit tests + 1 registry multi-room offline test + 3
integ + 13 mesh + 8 pi_forward + 10 presence + 2 parity + 19 rooms). Commit
`3ea9426` scoped to peers/presence_state.rs (new) + registry + connections + rooms
+ mod + story .md; relay-only, no generated files.

Presence-transition extraction verified: `PresenceState` + `PresenceTransition`
enum (BecameOnline/StayedOnline/BecameOffline/StayedOnlineAfterDisconnect) in
presence_state.rs; `register`/`unregister` call it via `ConnectionRegistry`
mutation facts (no implicit booleans inline); `is_online` delegates to
`connections.is_online` (connection-state source of truth, no second online
table). Duplicate-online + multi-room-offline invariants preserved: duplicate
connections suppress extra `peer_online` (+ suppressed counter); `peer_offline`
waits until the final live room/connection is gone (registry multi-room test).
`PresenceManager::snapshot` unchanged. `ConnectionInsert`/`ConnectionRemove`
facts extended with affected `peer_id` + `removed_connection` no-op guard so the
transition functions are pure + testable.
