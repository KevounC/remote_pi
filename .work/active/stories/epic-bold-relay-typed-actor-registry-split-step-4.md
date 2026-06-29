---
id: epic-bold-relay-typed-actor-registry-split-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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

- [ ] Connection, room-state, and presence-state modules do not directly depend on event subscribers/metrics except through the publisher/facade.
- [ ] Event JSON snapshots match current tests/fixtures.
- [ ] Register/unregister/update paths are clearly state mutation followed by event publication.
- [ ] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Risk

Medium. Event shapes are client-visible even though this is structural, so serialization must remain byte-compatible enough for existing deserializers.

## Rollback

Inline publisher methods back into `PeerRegistry` while retaining extracted state modules if they remain useful.
