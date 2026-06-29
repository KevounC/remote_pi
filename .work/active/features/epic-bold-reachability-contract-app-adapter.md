---
id: epic-bold-reachability-contract-app-adapter
kind: feature
stage: drafting
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract
depends_on: [epic-bold-reachability-contract-state-machine]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Reachability — app ConnectionManager adapter

## Brief
`ConnectionManager` becomes an adapter over the canonical `Reachability`
contract. Its private backoff/timer booleans (`_retryAttempt`, `_missedPings`,
`_connectInFlight`, `_retryTimer`, `_pingTimer`) collapse into the contract.
The cleanest existing implementation (it already has an explicit
`ConnectionStatus` sealed class) becomes the reference the others adopt.

## Epic context
- Parent epic: `epic-bold-reachability-contract`
- Position: consumer of `reachability-state-machine`.

## Foundation references
- Evidence: `app/lib/data/transport/connection_manager.dart:70-155`,
  `:556-785`, `:1041-1180`.

<!-- /agile-workflow:refactor-design fills in the adapter extraction. -->
