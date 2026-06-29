---
id: epic-bold-relay-typed-actor-registry-split
kind: feature
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor
depends_on: [epic-bold-relay-typed-actor-frame-dispatch, epic-bold-relay-typed-actor-control-handlers]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Relay typed actor — PeerRegistry split

## Brief
`PeerRegistry.senders` (`relay/src/peers/registry.rs:55`) is secretly five
things: connection registry, room registry, presence source, broadcast bus, and
room-metadata store. Split it into a connection registry + room/presence index
+ metadata store. `forward_to_peer` fanout is already retired by
`epic-bold-canonical-session-relay-opaque-targeting`.

## Epic context
- Parent epic: `epic-bold-relay-typed-actor`
- Position: consumer of `frame-dispatch`.

## Foundation references
- Evidence: `relay/src/peers/registry.rs:1-70`, `:210-350`, `:369-384`.

<!-- /agile-workflow:refactor-design pins the three-way split. -->

## Design decisions

- **Refactor lane retained**: this remains `[refactor]`. The split preserves relay wire shape, room/presence event timing, metadata merge-patch behavior, sender rewrite semantics, transport-error shapes, and relay opacity. Any canonical-session room targeting that has not landed by implementation time must stay out of this item.
- **Implementation order**: registry-split is the relay-typed-actor epic's final structural child. Step 1 depends explicitly on `epic-bold-relay-typed-actor-frame-dispatch` and also on `epic-bold-relay-typed-actor-control-handlers` so implementers inherit the `ConnectionActor` and typed handler seams instead of designing a second actor boundary.
- **Generated-contract posture**: use generated/re-exported Rust relay types from `epic-bold-generated-protocol-rust-codegen` through the actor/control-handler boundaries. Do not introduce new handwritten wire structs while splitting state.
- **Split shape**: `PeerRegistry` becomes a compatibility facade over actor-owned state: a connection table/delivery adapter, a room metadata/index store, and a presence transition publisher. The facade may keep the current public name during migration, but it must stop owning all responsibilities in one `senders` map.
- **Single-source state**: live connection membership is the source for online/offline and first/last-room transitions. Any indexes introduced for speed must be updated only inside the same mutation path as the connection table and must be tested against duplicate-room and stale-unregister cases.
- **Current-code discrepancy**: the feature brief says `forward_to_peer` fanout is already retired by canonical-session targeting, but this checkout still has `PeerRegistry::forward_to_peer`. This design preserves the current API while re-homing it in the delivery adapter; if canonical-session removes it before implementation, do not resurrect it.
- **Patchbay posture**: the target names relay-neutral concepts (`connections`, `room_state`, `presence_events`, `delivery`) and keeps endpoint `session_id` opaque. Future patchbay migration can replace the transport/schema source without unwinding relay-owned session semantics.
- **Dispatch rationale**: direct-read design only. The target was a bounded relay module with required sibling designs already landed; this delegated harness had no usable `subagent` tool, so no exploratory sub-delegation was spawned. Raised-tier coverage is this openai-codex worker pass; review remains an autopilot completion concern.
- **Cycle check**: `.work/bin/work-view --blocking` is absent in this checkout. A frontmatter graph check over active items plus the five proposed stories passed. The feature and step 1 depend on `frame-dispatch` and `control-handlers`; steps 2-5 chain linearly and no item points back to them.

## Code-smell scan findings

1. **God registry** — `relay/src/peers/registry.rs` owns connection IDs, live senders, room lifecycle, room metadata, presence transitions, broadcast delivery, and metrics in one type. High value: the actor gets narrow state owners.
2. **Duplicated metadata in connection entries** — `ConnEntry = (u64, RoomMeta, Sender)` stores room metadata per connection; duplicate connections at one `(peer, room)` mutate multiple copies and `rooms_of` relies on `v.last()`. High value: one room metadata store makes merge-patch behavior explicit.
3. **Implicit presence source** — online/offline transitions are inferred by scanning `senders` keys inside register/unregister. High value: a presence transition component can make first/last connection behavior testable without mixing broadcast code into the table.
4. **Broadcast bus hidden in registry** — `forward_to_all_rooms_of` is private delivery infrastructure used by room and presence events, while direct routing and cross-PC forwarding share the same map. High value: delivery becomes an adapter over the connection table.
5. **Lifecycle event code under one lock boundary** — register/unregister compute state changes under the sender lock and then emit JSON afterward, but the event plan is implicit tuple booleans. High value: explicit transition records reduce future actor/control-handler coupling.
6. **No project-specific refactor convention catalog** — `.agents/skills/refactor-conventions/` is absent; no convention-driven step was added beyond the default refactor-design lenses.

## Refactor Overview

`PeerRegistry` is the relay's live-state choke point. The type name says "peer registry," but the implementation is a connection registry, room index, metadata store, presence source, and broadcast bus coupled through one `HashMap<(peer_id, room_id), Vec<(conn_id, RoomMeta, Sender)>>`. The typed actor work gives the relay a clean dispatch boundary; this split gives the actor clean state boundaries.

The target is behavior-preserving and intentionally staged behind a compatibility facade. First extract the connection table and delivery adapter without changing call sites. Then move room metadata/lifecycle to a room-state store, make presence transitions explicit, move event publication out of the table, and finally collapse `PeerRegistry` into a composed actor-owned registry facade. Existing tests for duplicate connections, skip-sender, room metadata merge-patch, room announcements, presence dedup, and cross-PC delivery become the safety net.

## Refactor Steps

### Step 1: Extract the connection table and delivery adapter
**Priority**: High
**Risk**: Medium
**Source Lens**: code smell / lifecycle ownership
**Files**: `relay/src/peers/registry.rs`, `relay/src/peers/connections.rs`, `relay/src/peers/mod.rs`, `relay/src/handlers/peer.rs`, `relay/src/handlers/pi_forward.rs`
**Story**: `epic-bold-relay-typed-actor-registry-split-step-1`

**Current State**:
```rust
type RoomKey = (String, String); // (peer_id, room_id)
type ConnEntry = (u64, RoomMeta, mpsc::UnboundedSender<Message>);

pub struct PeerRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnEntry>>>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}

pub fn forward(&self, dest_peer: &str, dest_room: &str, msg: Message, from_conn_id: u64) -> bool { /* reads senders */ }
pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool { /* reads senders */ }
```

**Target State**:
```rust
pub(crate) type RoomKey = (String, String);

pub(crate) struct ConnectionEntry {
    pub conn_id: u64,
    pub room_meta: RoomMeta, // kept for step-1 compatibility; removed in step 2
    pub tx: mpsc::UnboundedSender<Message>,
}

pub(crate) struct ConnectionRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnectionEntry>>>,
}

impl ConnectionRegistry {
    pub fn insert(&self, peer_id: &str, room_meta: RoomMeta, tx: mpsc::UnboundedSender<Message>) -> ConnectionInsert;
    pub fn remove(&self, peer_id: &str, room_id: &str, conn_id: u64) -> ConnectionRemove;
    pub fn send_to_room(&self, dest_peer: &str, dest_room: &str, msg: Message, skip_conn_id: u64) -> bool;
    pub fn send_to_peer(&self, peer_id: &str, msg: Message) -> bool;
    pub fn send_to_all_rooms_of(&self, peer_id: &str, msg: Message);
}
```

**Implementation Notes**:
- Keep `PeerRegistry` as the public facade for this step; delegate existing methods to `ConnectionRegistry`.
- Preserve exact duplicate-room, skip-sender, stale-unregister, `forward_to_peer`, and no-content-inspection behavior.
- `ConnectionInsert`/`ConnectionRemove` should return prior/after facts (`was_offline_before`, `is_first_in_room`, `room_emptied`, `peer_offlined`) rather than letting the facade rescan ad hoc.
- If canonical-session has already removed `forward_to_peer`, map the new room-targeted delivery API instead of reintroducing peer-wide fanout.

**Acceptance Criteria**:
- [ ] `senders` and `next_conn` live in `ConnectionRegistry`, not directly in `PeerRegistry`.
- [ ] Existing public `PeerRegistry` callers compile with no behavior changes.
- [ ] Duplicate room, skip-sender, stale unregister, and cross-PC delivery tests still pass.
- [ ] Relay `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

**Rollback**: Inline `ConnectionRegistry` back into `PeerRegistry` and restore the previous tuple `ConnEntry` map. No wire/client behavior or persisted state changes are involved.

---

### Step 2: Move room lifecycle and metadata into a room-state store
**Priority**: High
**Risk**: High
**Source Lens**: missing abstraction / single source of truth
**Files**: `relay/src/peers/registry.rs`, `relay/src/peers/rooms.rs` or `relay/src/rooms/state.rs`, `relay/src/rooms.rs`, `relay/src/handlers/control.rs`, `relay/src/handlers/peer.rs`
**Story**: `epic-bold-relay-typed-actor-registry-split-step-2`

**Current State**:
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

pub async fn update_room_meta(&self, peer_id: &str, room_id: &str, patch: RoomMetaPatch) -> bool {
    /* mutates every ConnEntry RoomMeta, then broadcasts room_meta_updated */
}
```

**Target State**:
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

pub(crate) struct RoomMetaPatchResult {
    pub changed: bool,
    pub snapshot: RoomMeta,
}
```

**Implementation Notes**:
- Remove `RoomMeta` from `ConnectionEntry` after the store is authoritative.
- Preserve current duplicate-connection semantics: a later connection for an existing `(peer, room)` may update the room snapshot used by `rooms_check`, but it must not emit another `room_announced`.
- Preserve `room_announced` only first connection, `room_ended` only last connection, and `RoomMetaPatch` absent/null/`working` semantics.
- Keep `session_id` opaque; room state stores/carries it but never routes by it.

**Acceptance Criteria**:
- [ ] There is one canonical `RoomMeta` per live `(peer, room)`.
- [ ] `rooms_of` and `update_room_meta` read/write the room-state store, not connection entries.
- [ ] Tests cover duplicate connection metadata compatibility, first/last room events, and `working` true/false/absent patches.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Restore `RoomMeta` to connection entries and move `rooms_of`/`update_room_meta` back to the sender map. Because no wire format changes, rollback is a pure code revert.

---

### Step 3: Make presence transitions an explicit actor-owned state boundary
**Priority**: High
**Risk**: Medium
**Source Lens**: code smell / convergent state
**Files**: `relay/src/peers/registry.rs`, `relay/src/peers/presence.rs` or `relay/src/presence/state.rs`, `relay/src/presence.rs`, `relay/src/handlers/control.rs`
**Story**: `epic-bold-relay-typed-actor-registry-split-step-3`

**Current State**:
```rust
let was_offline_before = !lock.keys().any(|(p, _)| p == &peer_id);
/* insert */
if was_offline_before { /* emit peer_online */ }

let peer_offlined = room_emptied && !lock.keys().any(|(p, _)| p == peer_id);
if peer_offlined {
    /* emit peer_offline */
    self.presence.record_offline(peer_id, now_ms).await;
    self.presence.unsubscribe_all(peer_id).await;
}
```

**Target State**:
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

**Implementation Notes**:
- Use facts returned by `ConnectionRegistry` mutations; do not create an independently drifting online table unless it is updated atomically with the connection table.
- `PresenceManager` may keep subscription graph and `last_offline_ts`; this step extracts transition calculation and cleanup orchestration from `PeerRegistry`.
- Preserve no duplicate `peer_online` on multi-device reconnects and no premature `peer_offline` while another room/connection remains live.

**Acceptance Criteria**:
- [ ] Online/offline transition calculation is named and unit-tested outside the registry facade.
- [ ] `is_online` uses the connection-state source, and `PresenceManager::snapshot` behavior is unchanged.
- [ ] `peer_online` emitted/suppressed metrics remain unchanged for duplicate connection cases.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Move the two boolean calculations back into `PeerRegistry::register`/`unregister` and keep the connection/room split from prior steps if stable.

---

### Step 4: Extract registry event publication from state mutation
**Priority**: Medium
**Risk**: Medium
**Source Lens**: missing abstraction / ports and adapters
**Files**: `relay/src/peers/registry.rs`, `relay/src/peers/events.rs`, `relay/src/peers/connections.rs`, `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/metrics.rs`
**Story**: `epic-bold-relay-typed-actor-registry-split-step-4`

**Current State**:
```rust
if is_first_in_room {
    let room_subs = self.rooms.subscribers_of(&peer_id).await;
    let msg = serde_json::to_value(&room_meta).expect("RoomMeta serialization is infallible");
    for sub in &room_subs {
        self.forward_to_all_rooms_of(sub, Message::Text(msg.clone()));
    }
}
```

**Target State**:
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

**Implementation Notes**:
- State mutation returns transition records; publisher serializes current event JSON and sends via the delivery adapter.
- Keep JSON event shapes exactly the same: `peer_online`, `peer_offline`, `room_announced`, `room_ended`, and `room_meta_updated`.
- Keep logs/metrics content-free and preserve emitted/suppressed counters.

**Acceptance Criteria**:
- [ ] `ConnectionRegistry` and room/presence state modules do not depend on `PresenceManager`, `RoomManager`, or `FirehoseMetrics` except through the publisher/facade.
- [ ] Event JSON snapshots match current tests/fixtures.
- [ ] Register/unregister/update paths are state mutation followed by event publication, not mixed responsibilities under one method body.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Inline publisher methods back into `PeerRegistry` while retaining extracted connection/room/presence modules if useful.

---

### Step 5: Replace the grab-bag registry with the composed actor-state facade
**Priority**: High
**Risk**: High
**Source Lens**: code smell / boundary clarity / patchbay readiness
**Files**: `relay/src/peers/registry.rs`, `relay/src/peers/mod.rs`, `relay/src/lib.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/control.rs`, `relay/src/handlers/pi_forward.rs`, relay registry tests
**Story**: `epic-bold-relay-typed-actor-registry-split-step-5`

**Current State**:
```rust
pub struct PeerRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnEntry>>>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}
```

**Target State**:
```rust
pub struct PeerRegistry {
    connections: Arc<ConnectionRegistry>,
    rooms: Arc<RoomStateStore>,
    presence: Arc<PresenceState>,
    events: Arc<RegistryEventPublisher>,
}

impl PeerRegistry {
    pub async fn register(&self, peer_id: String, room_meta: RoomMeta, tx: mpsc::UnboundedSender<Message>) -> u64;
    pub async fn unregister(&self, peer_id: &str, room_id: &str, conn_id: u64);
    pub fn forward(&self, dest_peer: &str, dest_room: &str, msg: Message, from_conn_id: u64) -> bool;
    pub fn rooms_of(&self, peer_id: &str) -> Vec<RoomMeta>;
    pub async fn update_room_meta(&self, peer_id: &str, room_id: &str, patch: RoomMetaPatch) -> bool;
}
```

**Implementation Notes**:
- Keep the `PeerRegistry` public facade until all typed actor call sites can move to narrower fields. Do not force unrelated call-site churn just to rename the facade.
- Update `ConnectionActor`/typed control handlers to depend on the narrow methods they actually need; prefer passing `ConnectionRegistry`/room state/delivery handles where a handler does not need the full facade.
- Delete obsolete tuple aliases and any helper that still makes the registry a hidden bus.
- If implementation has an already-renamed `RelayActorState`, preserve the split shape rather than the exact name above.

**Acceptance Criteria**:
- [ ] `PeerRegistry` no longer directly owns the sender map, room metadata, presence transitions, event serialization, and metrics as one grab-bag.
- [ ] Actor/control/pi-forward call sites use the narrow state/delivery surface or the compatibility facade intentionally.
- [ ] Existing registry tests still cover routing, duplicate connections, stale unregister, presence transitions, room lifecycle, and metadata patches.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Revert this composition step to the step-4 facade. Earlier extracted modules can remain if the public composition proves too much call-site churn.

## Implementation Order

1. `epic-bold-relay-typed-actor-registry-split-step-1` (depends on `epic-bold-relay-typed-actor-frame-dispatch` and `epic-bold-relay-typed-actor-control-handlers`)
2. `epic-bold-relay-typed-actor-registry-split-step-2`
3. `epic-bold-relay-typed-actor-registry-split-step-3`
4. `epic-bold-relay-typed-actor-registry-split-step-4`
5. `epic-bold-relay-typed-actor-registry-split-step-5`

## Atomic steps acknowledged

- Step 2 is the semantically sensitive step because it changes `RoomMeta` from per-connection copies to one canonical per-room snapshot. The target must preserve the current duplicate-connection `rooms_of` semantics and merge-patch broadcasts.
- Step 5 is the final switch-over from grab-bag to composed state. It is high risk but rollback-isolated to the facade shape if steps 1-4 landed cleanly.
- Cross-PC room targeting and canonical `session_id` enforcement remain outside this refactor. Preserve whatever delivery behavior exists when implementation begins; do not use this split to change routing semantics.

## Verification plan

For each story, run from `relay/`:

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
```

Targeted tests should preserve duplicate-room registration, skip-sender delivery, stale unregister no-op, first-room `room_announced`, last-room `room_ended`, offline/online dedup and metrics, `rooms_check` snapshots, `room_meta_updated` merge-patch semantics, and cross-PC delivery/transport-error behavior.
