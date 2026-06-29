---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module
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

# Split pi-extension index — owner multiplexer module

## Brief
`_activePeers` fanout (`_broadcastToActive`, `index.ts:620-635`) + pairing as a
named module. Globals `_activePeers`, `_peerShort`, `_meshNode`, `_sessionName`,
`_sessionPeerCount`, `_hasGlobalPairings` (`index.ts:160-195`) become this
module's private state.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:160-195`, `:620-635`, `:1157-1167`,
  `:1238-1244`.

<!-- /agile-workflow:refactor-design pins the module boundary. -->
