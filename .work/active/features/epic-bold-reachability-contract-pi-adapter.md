---
id: epic-bold-reachability-contract-pi-adapter
kind: feature
stage: implementing
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
pi-extension’s relay reconnect and `MeshNode` relay reconnect should adopt
`Reachability` contract values and keep behavior intact. Retire duplicated
`RECONNECT_BACKOFFS_MS` constants in:

- `pi-extension/src/index.ts`
- `pi-extension/src/session/mesh_node.ts`

and liveness constants in:

- `pi-extension/src/transport/relay_client.ts`

while preserving reconnect/ping timing and ordering.

## Epic context
- Parent epic: `epic-bold-reachability-contract`
- Position: downstream consumer of `epic-bold-reachability-contract-state-machine`.

## Foundation references
- Evidence: `pi-extension/src/index.ts`, `pi-extension/src/session/mesh_node.ts`,
  `pi-extension/src/transport/relay_client.ts`,
  `.orchestration/contracts/reachability.json`.

## Refactor Design Notes
- Behavior-preserving only: no timing or ordering changes; no wire format changes.
- Keep patchbay migration unblocked by making this a thin, value-only adapter in
  `pi-extension/`.
- `Step-1` explicitly depends on `epic-bold-reachability-contract-state-machine`.
- No changes outside `pi-extension/`.

## Adapter shape
Use a new pure projection module:

- `pi-extension/src/reachability/reachability_contract.ts`

with exports:

```ts
export const REACHABILITY_BACKOFF_MS: readonly number[];
export function reachabilityBackoffMs(attempt: number): number;
export const REACHABILITY_RELAY_PING_INTERVAL_MS: number;
export const REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS: number;
export const REACHABILITY_RELAY_LIVENESS_CHECK_MS: number;
```

Design rationale: pi-extension has only policy reuse here; a full
state-machine adapter is over-factoring for this cycle and risks behavior
regressions. This adapter is therefore intentionally value-only.

A small unit test in `pi-extension/src/reachability/reachability_contract.test.ts`
must assert these values match `.orchestration/contracts/reachability.json` and
document drift if the source-of-truth changes.

## Cycle check
- `feature`: depends on `epic-bold-reachability-contract-state-machine`
- `story-1`: depends on `epic-bold-reachability-contract-state-machine`
- `story-2`: depends on `story-1`
- `story-3`: depends on `story-2`
- `story-4`: depends on `story-3`

No reverse edge, no cycles.

## Refactor steps

### Step 1: Add the pi-extension reachability policy projection

**Files**: `pi-extension/src/reachability/reachability_contract.ts`,
`pi-extension/src/reachability/reachability_contract.test.ts`

#### Current State
Reachability timing policy is duplicated as literals:

```ts
// index.ts
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];

// mesh_node.ts
private static readonly RELAY_RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];

// relay_client.ts
const LIVENESS_TIMEOUT_MS = 70_000;
const LIVENESS_CHECK_MS = 20_000;
```

#### Target State
Create one value module and contract test:

```ts
// pi-extension/src/reachability/reachability_contract.ts
export const REACHABILITY_BACKOFF_MS = [1_000, 2_000, 5_000, 10_000, 30_000] as const;
export const REACHABILITY_RELAY_PING_INTERVAL_MS = 25_000;
export const REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS = 70_000;
export const REACHABILITY_RELAY_LIVENESS_CHECK_MS = 20_000;

export function reachabilityBackoffMs(attempt: number): number {
  const idx = Math.min(attempt, REACHABILITY_BACKOFF_MS.length - 1);
  return REACHABILITY_BACKOFF_MS[idx] ?? REACHABILITY_BACKOFF_MS[REACHABILITY_BACKOFF_MS.length - 1]!;
}
```

#### Design/Acceptance
- Exported values become the local single source for all pi-extension reachability
  timers.
- Unit test asserts the projection equals `.orchestration/contracts/reachability.json`
  heartbeat/backoff values.

#### Risk
Low. Only import surface changes if later refactoring inverts the contract.

#### Rollback
Delete the module and restore in-file constants in all three consumers.

### Step 2: Replace index.ts reconnect backoff ladder with projection

**Files**: `pi-extension/src/index.ts`

#### Current State
`_scheduleReconnect` indexes local `RECONNECT_BACKOFFS_MS` directly.

#### Target State
Use projection helpers:

```ts
import {
  REACHABILITY_BACKOFF_MS,
  reachabilityBackoffMs,
} from "./reachability/reachability_contract";

const idx = Math.min(_reconnectAttempt, REACHABILITY_BACKOFF_MS.length - 1);
const delay = reachabilityBackoffMs(_reconnectAttempt);
```

#### Acceptance
- Existing extension reconnect tests keep expected delays `1s,2s,5s,10s,30s...`.
- Reconnect counter reset behavior unchanged after successful reconnect.
- No user-visible state transitions introduced.

#### Risk
Medium. This path runs on all relay reconnects; mistakes regress live reconnect.

#### Rollback
Inline the local ladder and revert imports in `index.ts` only.

### Step 3: Replace MeshNode relay reconnect backoff with projection

**Files**: `pi-extension/src/session/mesh_node.ts`

#### Current State
`MeshNode` stores its own static backoff constant and schedules reconnect via
that array.

#### Target State
Replace static array with shared exports:

```ts
import { REACHABILITY_BACKOFF_MS, reachabilityBackoffMs } from "../reachability/reachability_contract";

const backoffs = REACHABILITY_BACKOFF_MS;
const delay = reachabilityBackoffMs(this.relayBackoffIdx);
```

#### Acceptance
- `MeshNode` retry cadence remains exactly `1,2,5,10,30` seconds with 30s cap.
- Existing `MeshNode` behavior around `reconnectWired`, `detach`, and backoff reset
  is unchanged.

#### Risk
Medium. This reconnect path can stall cross-PC routing if mis-timed.

#### Rollback
Remove projection import and restore `RELAY_RECONNECT_BACKOFFS_MS` local constant.

### Step 4: Replace relay_client liveness windows with projection

**Files**: `pi-extension/src/transport/relay_client.ts`

#### Current State
Hard-coded watchdog constants:

```ts
const LIVENESS_TIMEOUT_MS = 70_000;
const LIVENESS_CHECK_MS = 20_000;
```

#### Target State
Use projection exports for the same values:

```ts
import {
  REACHABILITY_RELAY_LIVENESS_CHECK_MS,
  REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS,
} from "../reachability/reachability_contract";
```

#### Acceptance
- `relay_client` tests for silent-half-open closure and ~25s keepalives still pass.
- No liveness cadence change.

#### Risk
Low. Watchdog constants affect stale relay detection.

#### Rollback
Reinstate inline local constants.
