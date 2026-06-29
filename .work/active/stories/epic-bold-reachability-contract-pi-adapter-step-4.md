---
id: epic-bold-reachability-contract-pi-adapter-step-4
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-reachability-contract-pi-adapter
depends_on: [epic-bold-reachability-contract-pi-adapter-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Consume shared liveness timings in RelayClient

## Current State
`pi-extension/src/transport/relay_client.ts` hard-codes relay liveness timing:

```ts
const LIVENESS_TIMEOUT_MS = 70_000;
const LIVENESS_CHECK_MS = 20_000;
```

## Target State
Import and use:

- `REACHABILITY_RELAY_LIVENESS_TIMEOUT_MS`
- `REACHABILITY_RELAY_LIVENESS_CHECK_MS`

from `src/reachability/reachability_contract.ts` in watchdog scheduling and
close decision logic.

## Notes
`AUTH_TIMEOUT_MS` and ping interval constants remain local here unless/until the
applicable contract field requires migration; keep behavior unchanged this cycle.

## Acceptance Criteria
- `relay_client.test.ts` assertions for:
  - closing after silence beyond timeout, and
  - surviving simulated relay ping frames (~25s cadence)
  continue to pass.
- No change in ping/reconnect user-visible behavior.

## Risk
Low/Medium. Watchdog behavior is timing-sensitive; preserve numeric identity.

## Rollback
Reinstate inline constants in `relay_client.ts`.
