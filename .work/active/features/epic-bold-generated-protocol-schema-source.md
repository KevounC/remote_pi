---
id: epic-bold-generated-protocol-schema-source
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-generated-protocol
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Generated protocol — canonical schema source

## Brief
The single canonical schema + validators: the one place a new wire message is
added. Covers all three transports (app↔pi chat/control, cross-PC
`pi_envelope`, cockpit↔pi control RPC). Every message is self-describing —
carries canonical session id, turn id, type — so no "1 pairing = 1 session"
assumption and no legacy-no-room fail-open path survives.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: the source the three codegen targets (Dart, TS, Rust) generate
  from. Parallel to the riskiest child — the schema can be defined while the
  Dart codegen feasibility is proven.

## Foundation references
- Evidence of current fragmentation: `pi-extension/src/protocol/types.ts`,
  `app/lib/protocol/protocol.dart`, `relay/src/protocol/outer.rs`,
  `relay/src/rooms.rs`, `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:372-385`.

<!-- /agile-workflow:refactor-design picks the schema language (JSON Schema /
Protobuf / TS-as-source) and validator approach. -->
