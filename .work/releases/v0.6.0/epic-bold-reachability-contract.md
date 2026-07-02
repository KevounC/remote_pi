---
id: epic-bold-reachability-contract
kind: epic
stage: done
tags: [refactor, bold, pi-extension, app, relay]
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Reachability is one contract, not five reimplementations

## Thesis
There is one "reachability" state machine hiding across every transport. Name
it once, implement it once, project from it everywhere.

## Lens
Unification

## Impact
The same backoff `[1, 2, 5, 10, 30]` appears verbatim in
`pi-extension/src/index.ts:586`, `MeshNode` (`session/mesh_node.ts:100`), and app
`ConnectionManager` (`connection_manager.dart:74`). Pings fire at 20s / 25s / 70s
across surfaces. Each surface keeps its own booleans (`_reconnectAttempt`,
`_missedPings`, `_connectInFlight`, `_retryTimer`, `_pingTimer`) encoding the
same unnamed states. A single `Reachability` contract — `Connecting / Online /
Degraded / Offline / Retrying` + one backoff policy — replaces all of them. The
app's `ConnectionManager` already has the cleanest version (an explicit
`ConnectionStatus` sealed class); lift it to the shared contract and adopt it in
pi-extension and the relay heartbeat path.

## Cost
Small. Mostly extraction + a shared policy module per language. Low risk — the
behavior is already correct, just duplicated. This is the smallest-leverage
epic of the scan but the most obvious duplication; fixing it once pays forever
and is a gentle on-ramp to the generated-protocol world.

## Child features (riskiest first)
- **epic-bold-reachability-contract-state-machine** *(riskiest — design this first; the
  state set and backoff policy are the contract everything else adopts)* — the
  canonical `Reachability` states + transition rules + backoff policy, defined
  once (in the protocol schema once that epic lands; standalone until then).
- epic-bold-reachability-app-adapter — `ConnectionManager` becomes an adapter
  over the contract; its private backoff/timer booleans collapse.
- epic-bold-reachability-pi-adapter — pi-extension relay client + `MeshNode`
  reconnect adopt the contract; retire their duplicated `RECONNECT_BACKOFFS_MS`.

## Decomposition

Decomposition pre-existed (bold-refactor scan) — child features listed above in "Child features (riskiest first". Advanced to implementing via epic-design Phase 1.5 short-circuit.
