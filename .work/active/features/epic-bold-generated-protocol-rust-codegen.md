---
id: epic-bold-generated-protocol-rust-codegen
kind: feature
stage: drafting
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Generated protocol — Rust serde codegen target

## Brief
Generate the Rust serde structs for `OuterEnvelope`, `RoomMeta`, and control
frames from the canonical schema, replacing the hand structs in
`relay/src/protocol/` and `rooms.rs`. The relay's private merge-patch
interpretation of `RoomMeta` (`rooms.rs:31-47`) derives from the same schema.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: consumer of `schema-source`. Relay keeps the `ct` payload opaque
  (it doesn't decode inner chat messages), so only the *relay-owned* types
  (outer envelope, room meta, control frames) are generated here.

## Foundation references
- Evidence: `relay/src/protocol/outer.rs:13`, `relay/src/rooms.rs:8`,
  `relay/src/handlers/peer.rs:135-186` (manual `hello.room_meta` JSON parse
  that should use a typed struct).

<!-- /agile-workflow:refactor-design fills in serde codegen + migration. -->
