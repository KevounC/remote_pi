---
id: epic-bold-relay-typed-actor-registry-split-step-5
kind: story
stage: done
tags: [refactor]
parent: epic-bold-relay-typed-actor-registry-split
depends_on: [epic-bold-relay-typed-actor-registry-split-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation

- Composed `PeerRegistry` as a thin facade over `Arc<ConnectionRegistry>`, `Arc<RoomStateStore>`, `Arc<PresenceState>`, and `Arc<RegistryEventPublisher>` while preserving the public lifecycle name and register/unregister behavior.
- Migrated live call sites to narrow state/delivery surfaces: `ConnectionActor` stores connection delivery, room state, and event publisher pieces; typed control handlers use those pieces for presence backfill/checks and room metadata patches; `pi_forward` now depends on `ConnectionRegistry` delivery rather than the full registry facade.
- Deleted obsolete facade broadcast helpers (`backfill_presence`, `is_online`, `forward`, `forward_to_peer`, `forward_to_room`) so production code no longer treats `PeerRegistry` as a hidden bus; registry tests exercise delivery through the composed connection piece. No obsolete tuple aliases lived in the owned facade/handler files; the extracted `RoomKey` alias remains untouched per the collision guard.
- Verification: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build` passed from `relay/`. `cargo test` covered 158 tests across unit, integration, mesh, cross-PC, presence, rooms, protocol parity, and doc-test targets.
- No-regression confirmation: routing, duplicate connections, stale unregister, presence transitions, room lifecycle, metadata patches, and cross-PC delivery/transport-error coverage all remained green.

## Review

Approved (2026-06-30) with HIGH-risk final-composition verification. Independently
re-ran: relay `cargo fmt --check` clean; `cargo clippy -- -D warnings` clean;
`cargo test` 158 passed / 0 failed (no regression — existing routing/duplicate/
stale-unregister/presence/room-lifecycle/metadata/cross-PC tests prove the facade
composition is correct). Commit `4b597f2` scoped to peers/registry.rs (facade) +
handlers/{connection_actor,control,pi_forward} (narrow-surface migration) + story
.md; relay-only, no generated files.

Facade composition verified: `PeerRegistry` is now a thin facade over
`Arc<ConnectionRegistry>` + `Arc<RoomStateStore>` + `Arc<PresenceState>` +
`Arc<RegistryEventPublisher>` — no longer a grab-bag owning the sender map, room
metadata, presence transitions, event serialization, and metrics. Call sites
migrated: `ConnectionActor` stores the narrow pieces; typed control handlers use
them for presence backfill/checks + room metadata patches; `pi_forward` depends
on `ConnectionRegistry` delivery (not the full facade). Obsolete facade broadcast
helpers (`backfill_presence`/`is_online`/`forward`/`forward_to_peer`/`forward_to_room`)
deleted so production code no longer treats PeerRegistry as a hidden bus. **registry-split arc complete (5/5).**
