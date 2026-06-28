---
source_handle: remote-pi-relay-registry-presence-rooms
fetched: 2026-06-28
source_path: relay/src/peers/registry.rs
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay registry, presence, rooms, and firehose metrics

Paraphrased summary: The relay's peer registry owns live WebSocket senders by `(peer_id, room_id)`, supports multiple live connections per room, emits presence/room transitions only on real state changes, and records dedup metrics.

## Key passages

- `PeerRegistry` stores `(peer_id, room_id)` to a vector of `(conn_id, RoomMeta, sender)`, allowing multiple live connections for the same human Owner/device key.
- `register()` fires `room_announced` only for the first connection in a room and `peer_online` only on offline-to-online transitions.
- `unregister()` emits `room_ended` only when the last connection in a room is removed and `peer_offline` only when the peer has no remaining rooms.
- `forward()` sends to all live connections for a destination `(peer, room)` except a specified sender connection id and never inspects message content.
- `RoomMeta` serializes `working` as a required boolean; `RoomMetaPatch` treats absent fields as leave-current, nullable string fields (`model`, `thinking`) as clearable by explicit null, and `working: false` as the cleared state.
- `PresenceManager` and `RoomManager` replace subscription lists on subscribe, remove selected peers on unsubscribe, and clean all subscriptions on disconnect.
- `FirehoseMetrics` tracks emitted/suppressed peer-online, presence, and rooms frames and logs one structured 10-second window only when counters are nonzero.

## Structural metadata

- Source type: Rust source set
- Paths: `relay/src/peers/registry.rs`, `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/metrics.rs`
