---
id: epic-bold-relay-typed-actor-registry-split-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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

- [ ] Presence transition calculation is outside the registry facade and has targeted tests.
- [ ] `is_online` still uses the connection-state source of truth.
- [ ] `peer_online` emitted/suppressed metrics remain unchanged for duplicate connection cases.
- [ ] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Risk

Medium. Presence events are deduped by edge transitions; a bad split can create notification firehose or hide real offline transitions.

## Rollback

Move transition booleans back into `PeerRegistry::register` and `PeerRegistry::unregister`, keeping earlier connection/room modules if they are stable.
