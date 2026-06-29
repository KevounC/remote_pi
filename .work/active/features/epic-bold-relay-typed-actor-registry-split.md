---
id: epic-bold-relay-typed-actor-registry-split
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
