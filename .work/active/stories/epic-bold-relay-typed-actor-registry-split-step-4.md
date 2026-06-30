---
id: epic-bold-relay-typed-actor-registry-split-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Extract registry event publication from state mutation

## Current State

```rust
if is_first_in_room {
    let room_subs = self.rooms.subscribers_of(&peer_id).await;
    let mut announced = serde_json::to_value(&room_meta).expect("RoomMeta serialization is infallible");
    announced["type"] = "room_announced".into();
    announced["peer"] = peer_id.as_str().into();
    for sub in &room_subs {
        self.forward_to_all_rooms_of(sub, Message::Text(announced.to_string()));
    }
}
```

State mutation, subscriber lookup, event JSON construction, metrics, and delivery are interleaved inside `PeerRegistry`.

## Target State

```rust
pub(crate) struct RegistryEventPublisher {
    delivery: Arc<ConnectionRegistry>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}

impl RegistryEventPublisher {
    pub async fn publish_room_announced(&self, peer_id: &str, room: &RoomMeta);
    pub async fn publish_room_ended(&self, peer_id: &str, ended: RoomEnded);
    pub async fn publish_presence_transition(&self, transition: PresenceTransition);
    pub async fn publish_room_meta_updated(&self, peer_id: &str, room_id: &str, snapshot: &RoomMeta);
}
```

Connection/room/presence state returns transition records; the publisher serializes and sends relay events.

## Implementation Notes

- Preserve exact event shapes: `peer_online`, `peer_offline`, `room_announced`, `room_ended`, and `room_meta_updated`.
- Keep logs/metrics content-free and preserve emitted/suppressed counters.
- The publisher is an adapter over the connection table; state modules must not know about WebSocket sink details.
- This is not a behavior change or backpressure redesign; keep current unbounded-channel semantics.

## Acceptance Criteria

- [x] Connection, room-state, and presence-state modules do not directly depend on event subscribers/metrics except through the publisher/facade.
- [x] Event JSON snapshots match current tests/fixtures.
- [x] Register/unregister/update paths are clearly state mutation followed by event publication.
- [x] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Risk

Medium. Event shapes are client-visible even though this is structural, so serialization must remain byte-compatible enough for existing deserializers.

## Rollback

Inline publisher methods back into `PeerRegistry` while retaining extracted state modules if they remain useful.

## Implementation

- Added `relay/src/peers/registry_event_publisher.rs` with `RegistryEventPublisher`, the adapter that owns subscriber lookup, event JSON construction, firehose metrics, and delivery over `ConnectionRegistry`.
- `PeerRegistry` now performs state mutation first (`ConnectionRegistry` + `RoomStateStore` + `PresenceState`) and then publishes the resulting room/presence transition through the publisher for register, unregister, and room metadata update paths.
- Preserved event-shape compatibility for `peer_online`, `peer_offline`, `room_announced`, `room_ended`, and `room_meta_updated` by moving the existing serialization logic intact; existing registry/presence/rooms tests continue to exercise deserializable snapshots.
- Added `RoomEnded.since_ts` as a transition fact so the publisher can emit `room_ended` without recomputing timestamps or mixing event details back into `PeerRegistry`.
- Verification passed from `relay/`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build`. Test counts: 103 lib tests, 0 main tests, 3 integration tests, 13 mesh tests, 8 pi-forward tests, 10 presence tests, 2 protocol parity tests, 19 rooms tests, and 0 doc-tests.

## Review

Approved (2026-06-30). Independently re-ran: relay `cargo fmt --check` clean;
`cargo clippy -- -D warnings` clean; `cargo test` 158 passed / 0 failed (103 lib +
3 integ + 13 mesh + 8 pi_forward + 10 presence + 2 parity + 19 rooms; pure
refactor — existing tests prove byte-compat). Commit `1eb287d` scoped to
peers/registry_event_publisher.rs (new) + registry.rs (shrunk ~120 lines) + rooms.rs
+ mod + story .md; relay-only, no generated files.

State-then-publish separation verified: `RegistryEventPublisher` extracted as the
adapter owning subscriber lookup + event JSON construction + firehose metrics +
delivery over ConnectionRegistry (4 publish methods: room_announced/room_ended/
presence_transition/room_meta_updated). `PeerRegistry` now does state mutation
first (ConnectionRegistry + RoomStateStore + PresenceState) THEN publishes the
transition. Event-shape byte-compat preserved (peer_online/peer_offline/
room_announced/room_ended/room_meta_updated serialization moved intact; existing
tests exercise deserializable snapshots). State modules no longer directly
depend on event subscribers/metrics. `RoomEnded.since_ts` transition-fact addition
is a clean way to emit without recomputing timestamps in the registry.
