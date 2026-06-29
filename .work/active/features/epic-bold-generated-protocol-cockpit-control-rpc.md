---
id: epic-bold-generated-protocol-cockpit-control-rpc
kind: feature
stage: drafting
tags: [refactor, bold, cockpit, pi-extension]
parent: epic-bold-generated-protocol
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Generated protocol — fold the cockpit NUL-prefix control RPC into the schema

## Brief
Retire the `\x00remote-pi-ctrl:` NUL-prefix string RPC between cockpit and
pi-extension. Today it's a private hand-mirrored string protocol
(`pi-extension/src/index.ts:146` `CTRL_PREFIX`, duplicated in
`cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:372-385`, with custom
event strings `remote-pi:relay-state`, `remote-pi:name-assigned`,
`remote-pi:pair-code`, `remote-pi:paired` mapped in
`cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart:91-116`). Fold it
into the generated schema so the magic prefix and custom strings can't drift.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: the schema spans two transports — relay (app↔pi, cross-PC) and
  Pi custom events (cockpit↔pi). This feature proves the schema can span both.

## Foundation references
- Evidence: `pi-extension/src/index.ts:146`, cockpit duplicates at
  `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:372-385`,
  `adapters/rpc_event_mapper.dart:91-116`,
  `core/data/relay/pairing_gateway_impl.dart:21-25`.

<!-- /agile-workflow:refactor-design fills in the transport-spanning schema +
migration of the magic prefix. -->
