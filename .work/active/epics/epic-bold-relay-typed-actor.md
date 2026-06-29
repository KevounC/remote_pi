---
id: epic-bold-relay-typed-actor
kind: epic
stage: implementing
tags: [refactor, bold, relay]
parent: null
depends_on: [epic-bold-generated-protocol]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# The relay connection is a typed-frame actor, not a JSON switch

## Thesis
An authenticated connection actor receives *typed* frames (generated from the
protocol schema) and dispatches to narrow handlers. The god-loop and the god-map
both split along their real seams.

## Lens
Inversion

## Impact
`relay/src/handlers/peer.rs`'s single `handle_peer` loop is auth handshake +
router + control-plane + rate limiter + room-metadata patcher + Pi-forwarding
gateway + heartbeat, all branching on raw `frame.get("type")` JSON
(`peer.rs:265-431`). `PeerRegistry.senders` (`registry.rs:55`) is secretly five
things: connection registry, room registry, presence source, broadcast bus, and
room-metadata store. An authenticated connection actor receiving typed frames
dispatches to narrow handlers; `PeerRegistry` splits into a connection
registry, a room/presence index, and a metadata store. Follows directly from the
generated-protocol epic (typed frames are its output).

## Cost
Medium. The relay is already the cleanest subsystem (`main.rs` light,
`lib.rs::build_router` small), so this is the lowest-risk structural epic.
Depends on generated-protocol for typed frames. Hardest part: `presence.rs` and
`rooms.rs` are near-duplicate subscription graphs — decide whether to unify them
or keep them separate-but-typed.

## Child features (riskiest first)
- **epic-bold-relay-typed-actor-frame-dispatch** *(riskiest — design this first;
  the typed-frame decode + dispatch shape is what the registry split and handler
  extraction both depend on)* — decode frames into generated typed enums; the
  connection actor dispatch loop replaces the raw-JSON switch.
- epic-bold-relay-typed-actor-registry-split — `PeerRegistry` splits into
  connection registry + room/presence index + metadata store; `forward_to_peer`
  fanout already retired by the canonical-session epic.
- epic-bold-relay-typed-actor-control-handlers — presence/rooms/`room_meta_update`
  become typed handlers; `presence.rs` vs `rooms.rs` duplication resolved.

## Decomposition

Decomposition pre-existed (bold-refactor scan) — child features listed above in "Child features (riskiest first". Advanced to implementing via epic-design Phase 1.5 short-circuit.
