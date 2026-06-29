---
id: epic-bold-relay-typed-actor-control-handlers-step-3
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-control-handlers
depends_on: [epic-bold-relay-typed-actor-control-handlers-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Factor the duplicated presence/rooms subscription graph

**Priority**: High  
**Risk**: Low  
**Source Lens**: missing abstraction / code smell  
**Files**: `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/subscriptions.rs` or `relay/src/control/subscriptions.rs`, `relay/src/lib.rs`

## Current State

`PresenceManager` and `RoomManager` carry near-identical subscription graph code:

```rust
struct Inner {
    subscribers_of: HashMap<String, HashSet<String>>,
    subscriptions_by: HashMap<String, HashSet<String>>,
    // presence-only: last_offline_ts
}

pub async fn subscribe(&self, subscriber: String, peers: Vec<String>) { /* replace full list */ }
pub async fn unsubscribe(&self, subscriber: &str, peers: Vec<String>) { /* remove subset */ }
pub async fn unsubscribe_all(&self, subscriber: &str) { /* cleanup */ }
pub async fn subscribers_of(&self, peer: &str) -> Vec<String> { /* lookup */ }
```

The duplication is easy to drift because the two managers share lifecycle rules but not source.

## Target State

Extract the common graph into one small internal abstraction and keep public manager APIs stable:

```rust
#[derive(Debug, Default)]
pub(crate) struct SubscriptionIndex {
    subscribers_of: HashMap<String, HashSet<String>>,
    subscriptions_by: HashMap<String, HashSet<String>>,
}

impl SubscriptionIndex {
    pub fn replace(&mut self, subscriber: String, peers: Vec<String>) { /* existing replace semantics */ }
    pub fn remove(&mut self, subscriber: &str, peers: Vec<String>) { /* existing subset removal */ }
    pub fn remove_all(&mut self, subscriber: &str) { /* existing cleanup */ }
    pub fn subscribers_of(&self, peer: &str) -> Vec<String> { /* existing lookup */ }
}
```

Presence keeps its extra offline timestamp state beside the shared graph:

```rust
struct PresenceInner {
    subscriptions: SubscriptionIndex,
    last_offline_ts: HashMap<String, i64>,
}
```

Rooms wraps only the shared graph:

```rust
struct RoomInner {
    subscriptions: SubscriptionIndex,
}
```

## Implementation Notes

- Preserve replacement semantics exactly: `subscribe(subscriber, [])` clears all watched peers and does not store an empty `subscriptions_by` entry.
- Preserve cleanup on disconnect for both managers.
- Keep `PresenceManager::snapshot` and `record_offline` as presence-specific behavior.
- Add or move unit tests to prove presence and rooms both share the same replace/remove/remove-all semantics.

## Acceptance Criteria

- [ ] The subscription graph implementation exists in one internal type used by both `PresenceManager` and `RoomManager`.
- [ ] Public `PresenceManager`/`RoomManager` APIs and serialized outputs remain unchanged.
- [ ] Existing presence and rooms subscription tests still pass.
- [ ] No room/presence control behavior changes are introduced.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Low. This is a contained internal deduplication. The main risk is accidentally changing empty-list unsubscribe-all semantics.

## Rollback

Inline `SubscriptionIndex` back into `presence.rs` and `rooms.rs`. Because public manager APIs remain stable, rollback does not affect actor handler code.
