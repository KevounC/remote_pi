---
id: epic-bold-reachability-contract-state-machine
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app, relay]
parent: epic-bold-reachability-contract
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Reachability — canonical state machine (riskiest — design first)

## Brief
The canonical `Reachability` states + transition rules + backoff policy,
defined once. State set: `Connecting / Online / Degraded / Offline / Retrying`,
with one backoff source (`[1, 2, 5, 10, 30]` today, duplicated verbatim in three
places). This is the contract every transport adapter adopts. Defined in the
protocol schema once that epic lands; standalone (shared policy module per
language) until then.

## Epic context
- Parent epic: `epic-bold-reachability-contract`
- Position: riskiest child — the state set and backoff policy are the contract
  the app/pi adapters adopt. Design FIRST.

## Foundation references
- Evidence: `pi-extension/src/index.ts:586` (`RECONNECT_BACKOFFS_MS`),
  `pi-extension/src/session/mesh_node.ts:100` (own copy),
  `app/lib/data/transport/connection_manager.dart:74` (`_kBackoff`),
  `app/lib/data/transport/connection_manager.dart:1-70` (cleanest existing
  state machine — `ConnectionStatus` sealed class — to lift from).

<!-- /agile-workflow:refactor-design pins the state set, transitions, backoff. -->
