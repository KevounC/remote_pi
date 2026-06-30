---
id: epic-bold-reachability-contract-pi-adapter-step-3
kind: story
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-reachability-contract-pi-adapter
depends_on: [epic-bold-reachability-contract-pi-adapter-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation notes
- Replaced `MeshNode`-local reconnect backoff constant and indexing in
  `pi-extension/src/session/mesh_node.ts` with shared reachability contract values.
  - Added imports for `REACHABILITY_BACKOFF_MS` and `reachabilityBackoffMs` from
    `pi-extension/src/reachability/reachability_contract`.
  - Removed `RELAY_RECONNECT_BACKOFFS_MS` static constant.
  - Replaced `_scheduleRelayReconnect()` delay calculation with
    `reachabilityBackoffMs(this.relayBackoffIdx)` while keeping all reconnect
    wiring, flags, and detach ordering intact.
- Added `pi-extension/src/session/mesh_node.test.ts` to lock behavior:
  - validates relay reconnect schedule delays remain
    `1_000, 2_000, 5_000, 10_000, 30_000` with cap.
  - validates successful bridge rebuild resets `relayBackoffIdx` to `0`.
- Verification:
  - `corepack pnpm typecheck`
  - `corepack pnpm exec vitest run src/reachability src/session/mesh_node`

## Review (2026-06-30, fast-lane)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 84402d8` — only `pi-extension/src/session/mesh_node.ts` + `mesh_node.test.ts` + this story; no `index.ts` collision with deferred pi-ext stories.
- Confirmed `MeshNode.RELAY_RECONNECT_BACKOFFS_MS` static constant removed; shared `reachability_contract.js` imports (`REACHABILITY_BACKOFF_MS`, `reachabilityBackoffMs`) wired into reconnect scheduling. Reconnect wiring/ownership flags unchanged.
- `corepack pnpm typecheck` clean (harmless npmrc EACCES + pnpm-field warnings only).
- `corepack pnpm exec vitest run src/reachability src/session/mesh_node` — 8/8 pass. New test `relay reconnect delays use the shared 1,2,5,10,30-second ladder with cap` asserts `delays === [1_000, 2_000, 5_000, 10_000, 30_000, 30_000]` (6th value proves cap). Reset-after-success test present.
- Acceptance criteria satisfied: ladder emits 1,2,5,10,30s with cap; reset-after-success unchanged; no MeshNode lifecycle/state-ownership changes beyond import replacement.
