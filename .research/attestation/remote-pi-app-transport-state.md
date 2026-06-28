---
source_handle: remote-pi-app-transport-state
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/app/lib/data/transport/connection_manager.dart
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi app transport and room-state source

Paraphrased summary: `ConnectionManager` owns relay connection status, peer/room presence snapshots, room metadata, retry/backoff, WebSocket liveness, and room working/live derivation. It treats presence and rooms as canonical snapshot maps emitted over streams, replays subscriptions on reconnect, gates live/working state on online status, and preserves cached room metadata while considering live room IDs authoritative for reachability.

## Key passages

- `ConnectionStatus` is a sealed state model with `StatusNoPeer`, `StatusConnecting`, `StatusOnline`, `StatusRetrying`, and `StatusOffline`.
- Presence and room streams emit full snapshot maps; callers should treat each event as the canonical state for all keys present.
- `_roomsByPeer` is the canonical cached plus announced room set; `_liveRoomIds` records which room IDs are alive in the current relay snapshot.
- `subscribeToPeers` sends presence and room subscriptions/checks together and stores normalized base64 peer keys for reconnect replay.
- `_replaySubscriptions` sends `subscribe_presence`, `presence_check`, `subscribe_rooms`, and `rooms_check` after reconnect.
- `RoomsSnapshot` merges the relay snapshot into cache and treats snapshot `working` as authoritative for live state.
- `isRoomLive` and `isRoomWorking` both return false when connection status is not online, because a dropped WebSocket means no fresh signal.
- `markRoomWorking` provides an app-side correction for the active room so missed/delayed relay metadata cannot leave the active tile stuck working.
- WebSocket ping handling separates app↔relay TCP liveness from protocol-level app↔Pi liveness.

## Structural metadata

- Source type: local Dart source
- Path: `/home/agent/forks/remote_pi/app/lib/data/transport/connection_manager.dart`
- Related local files read in this engagement: `ws_transport.dart`, `sync_service.dart`, `domain/session_state.dart`.
