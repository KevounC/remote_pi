---
id: epic-bold-reachability-contract-pi-adapter-step-3
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-reachability-contract-pi-adapter
depends_on: [epic-bold-reachability-contract-pi-adapter-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Consume shared backoff policy in MeshNode relay reconnect

## Current State
`MeshNode` owns its own static `RELAY_RECONNECT_BACKOFFS_MS` and schedules
reconnect using that constant.

```ts
private static readonly RELAY_RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
// ...
const backoffs = MeshNode.RELAY_RECONNECT_BACKOFFS_MS;
const delay = backoffs[Math.min(this.relayBackoffIdx, backoffs.length - 1)];
```

## Target State
Use `reachability_contract.ts` exports and helper in reconnect scheduling and
attempt methods.

```ts
import { REACHABILITY_BACKOFF_MS, reachabilityBackoffMs } from "../reachability/reachability_contract";
const delay = reachabilityBackoffMs(this.relayBackoffIdx);
const backoffs = REACHABILITY_BACKOFF_MS;
```

## Notes
Keep all existing reconnect wiring flags (`reconnectWired`, `relay` attachment,
`detach` ordering) unchanged.

## Acceptance Criteria
- Mesh relay reconnect delay ladder still emits `1,2,5,10,30` seconds with cap.
- Reset behavior after successful reconnect remains unchanged.
- No `MeshNode` lifecycle/state-ownership changes beyond import replacement.

## Risk
Medium. A wrong delay source here affects cross-PC routing repair after relay
outage.

## Rollback
Remove projection imports and restore `RELAY_RECONNECT_BACKOFFS_MS` and local
indexing logic.
