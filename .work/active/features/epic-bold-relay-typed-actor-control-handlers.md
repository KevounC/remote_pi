---
id: epic-bold-relay-typed-actor-control-handlers
kind: feature
stage: drafting
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor
depends_on: [epic-bold-relay-typed-actor-frame-dispatch]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Relay typed actor — typed control handlers

## Brief
`presence.rs` and `rooms.rs` are near-duplicate subscription graphs
(`presence.rs:1-108` vs `rooms.rs:1-126`). Presence/rooms/`room_meta_update`
become typed handlers dispatched from the connection actor. The
`presence.rs`/`rooms.rs` duplication is resolved — either unified or kept
separate-but-typed per the design pass. Bad `peers` frames (which today become
an empty list, silently unsubscribing everything — `relay/src/handlers/peer.rs:56-68`)
fail-closed.

## Epic context
- Parent epic: `epic-bold-relay-typed-actor`
- Position: consumer of `frame-dispatch`.

## Foundation references
- Evidence: `relay/src/presence.rs:1-108`, `relay/src/rooms.rs:1-126`,
  `relay/src/handlers/peer.rs:56-68`, `:285-431`.

<!-- /agile-workflow:refactor-design resolves the presence/rooms duplication. -->
