---
id: epic-bold-relay-typed-actor-frame-dispatch
kind: feature
stage: drafting
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Relay typed actor — typed-frame dispatch (riskiest — design first)

## Brief
Decode incoming frames into generated typed enums (from
`epic-bold-generated-protocol`) and dispatch via a connection actor loop that
replaces the raw-JSON switch in `handle_peer` (`relay/src/handlers/peer.rs:265-431`,
branching on `frame.get("type").as_str()`). The typed-frame decode + dispatch
shape is what the registry split and handler extraction both depend on, so it
lands first.

## Epic context
- Parent epic: `epic-bold-relay-typed-actor`
- Position: riskiest child — the dispatch shape is what the rest hangs on.
  Design FIRST. Depends on the generated-protocol epic for typed frames.

## Foundation references
- Evidence: `relay/src/handlers/peer.rs:118-431` (god loop), `:135-186`
  (manual `hello.room_meta` JSON parse).

<!-- /agile-workflow:refactor-design pins the actor + typed dispatch shape. -->
