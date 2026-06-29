---
id: epic-bold-relay-typed-actor-registry-split-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Replace the grab-bag registry with the composed actor-state facade

## Current State

```rust
pub struct PeerRegistry {
    next_conn: AtomicU64,
    senders: Mutex<HashMap<RoomKey, Vec<ConnEntry>>>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}
```

The public registry type directly owns and coordinates every live-state responsibility.

## Target State

```rust
pub struct PeerRegistry {
    connections: Arc<ConnectionRegistry>,
    rooms: Arc<RoomStateStore>,
    presence: Arc<PresenceState>,
    events: Arc<RegistryEventPublisher>,
}
```

`PeerRegistry` is a compatibility facade over narrow actor-owned state. Actor/control/pi-forward call sites can depend on the narrow pieces where appropriate.

## Implementation Notes

- Keep the public `PeerRegistry` name until broader call sites can migrate safely; do not introduce churn-only renames.
- Update `ConnectionActor`, typed control handlers, and `pi_forward` to depend on the narrow state/delivery surface when they do not need the full facade.
- Delete obsolete tuple aliases and helpers that keep the registry as a hidden broadcast bus.
- If implementation has already introduced `RelayActorState`, keep the split shape even if exact names differ.
- Do not use this step to change canonical-session routing, cross-PC room targeting, or endpoint-owned `session_id` semantics.

## Acceptance Criteria

- [ ] `PeerRegistry` no longer directly owns the sender map, room metadata, presence transitions, event serialization, and metrics as one grab-bag.
- [ ] Actor/control/pi-forward call sites use a narrow state/delivery surface or the compatibility facade intentionally.
- [ ] Registry tests still cover routing, duplicate connections, stale unregister, presence transitions, room lifecycle, metadata patches, and cross-PC delivery/transport errors.
- [ ] From `relay/`: `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass.

## Risk

High. This is the final composition switch and touches most relay live-state call sites, even though each underlying behavior should already be protected by earlier steps.

## Rollback

Revert this composition step to the step-4 facade. Earlier extracted modules can remain if the public composition creates too much call-site churn.
