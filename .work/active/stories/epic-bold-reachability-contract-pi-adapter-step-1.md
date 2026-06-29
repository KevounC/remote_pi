---
id: epic-bold-reachability-contract-pi-adapter-step-1
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-reachability-contract-pi-adapter
depends_on: [epic-bold-reachability-contract-state-machine]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Add pi-extension reachability contract projection module

## Current State
pi-extension carries its own duplicated timing ladders for reconnect and liveness:

```ts
// index.ts
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];

// session/mesh_node.ts
private static readonly RELAY_RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];

// transport/relay_client.ts
const LIVENESS_TIMEOUT_MS = 70_000;
const LIVENESS_CHECK_MS = 20_000;
```

No single `pi-extension`-owned artifact enforces them against the canonical
contract.

## Target State
Create a pure projection module and parity test:

- `pi-extension/src/reachability/reachability_contract.ts`
- `pi-extension/src/reachability/reachability_contract.test.ts`

```ts
export const REACHABILITY_BACKOFF_MS = [1_000, 2_000, 5_000, 10_000, 30_000] as const;
export const REACHABILITY_RELAY_PING_INTERVAL_MS = 25_000;
export const REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS = 70_000;
export const REACHABILITY_RELAY_LIVENESS_CHECK_MS = 20_000;

export function reachabilityBackoffMs(attempt: number): number {
  const idx = Math.min(attempt, REACHABILITY_BACKOFF_MS.length - 1);
  return REACHABILITY_BACKOFF_MS[idx] ?? REACHABILITY_BACKOFF_MS[REACHABILITY_BACKOFF_MS.length - 1]!;
}
```

- Test reads `protocol/schema/reachability.json` and asserts that
  backoff and liveness values are in sync.

## Notes
This step is intentionally value-only: no new runtime dependency on JSON in
application code, only a focused test asserting drift.

## Acceptance Criteria
- `reachability_contract.ts` exports backoff + relay liveness constants.
- `reachabilityBackoffMs` clamps attempt indices at the final ladder entry.
- `reachability_contract.test.ts` fails if `reachability.json` diverges from code.

## Risk
Low. The only risk is future contract schema drift; tests make it fail fast.

## Rollback
Remove the new module and tests; restore in-file constants in all consumers.
