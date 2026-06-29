---
id: epic-bold-reachability-contract-pi-adapter
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension]
parent: epic-bold-reachability-contract
depends_on: [epic-bold-reachability-contract-state-machine]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Reachability — pi-extension relay + mesh adapter

## Brief
pi-extension's relay client reconnect and `MeshNode` relay reconnect adopt the
canonical `Reachability` contract. Retire the duplicated
`RECONNECT_BACKOFFS_MS` in `pi-extension/src/index.ts:586` and
`session/mesh_node.ts:100`, and the liveness constants in
`transport/relay_client.ts:17`.

## Epic context
- Parent epic: `epic-bold-reachability-contract`
- Position: consumer of `reachability-state-machine`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:586`, `session/mesh_node.ts:100`,
  `transport/relay_client.ts:17`.

<!-- /agile-workflow:refactor-design fills in the adapter extraction. -->
