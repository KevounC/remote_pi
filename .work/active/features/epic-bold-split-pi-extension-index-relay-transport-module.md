---
id: epic-bold-split-pi-extension-index-relay-transport-module
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Split pi-extension index — relay transport module

## Brief
Relay transport lifecycle (reconnect, liveness, control frames) extracted from
`index.ts` as a named module. Adopts the `epic-bold-reachability-contract`
state machine. Globals `_relay`, `_lastRelayStatus`, `_relayUrl`,
`_reconnectTimer`, `_reconnectAttempt` (`index.ts:128-147`, `:587-588`) become
this module's private state.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:128-147`, `:587-588`;
  `pi-extension/src/transport/relay_client.ts`.

<!-- /agile-workflow:refactor-design pins the module boundary. -->
