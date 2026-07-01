---
id: epic-bold-reachability-contract-pi-adapter-step-2
kind: story
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-reachability-contract-pi-adapter
depends_on: [epic-bold-reachability-contract-pi-adapter-step-1]
release_binding: extension-0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 2: Consume the shared backoff policy in extension relay reconnect

## Current State
`pi-extension/src/index.ts` computes reconnect delay from module-local constant and
`_reconnectAttempt` in `_scheduleReconnect`.

```ts
const idx = Math.min(_reconnectAttempt, RECONNECT_BACKOFFS_MS.length - 1);
const delay = RECONNECT_BACKOFFS_MS[idx]!;
_reconnectAttempt += 1;
```

## Target State
Import shared constants/helpers from `src/reachability/reachability_contract.ts` and
use them in `_scheduleReconnect`, keeping all control flow untouched.

```ts
import { reachabilityBackoffMs } from "./reachability/reachability_contract";

const delay = reachabilityBackoffMs(_reconnectAttempt);
```

- Remove now-redundant local `RECONNECT_BACKOFFS_MS` definition.
- Preserve `_reconnectAttempt` reset on successful reconnect and timer
  cancellation semantics.

## Notes
No reconnect state machine changes; only policy read source is changed. This keeps
`_state`, `_reconnectTimer` lifecycle, and teardown ordering intact.

## Acceptance Criteria
- Reconnect delay progression remains `1s,2s,5s,10s,30s,30s...`.
- Successful reconnect still resets retry attempt to restart next wait at 1s.
- Existing reconnect tests (`extension.test.ts`) remain stable in intent.

## Risk
Medium. This is the only reconnect ladder driving live relay recovery.

## Rollback
Reintroduce local backoff array in `index.ts` and remove projection import.

## Implementation notes
- Files changed: `pi-extension/src/index.ts`.
- Tests added: none; consumed the projection covered by `reachability_contract.test.ts`.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm exec vitest run src/reachability/reachability_contract.test.ts` passed.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Implementation commit `11007b5` replaces the local reconnect backoff array in `pi-extension/src/index.ts` with `reachabilityBackoffMs(_reconnectAttempt)` while preserving increment/reset/timer control flow. Verification run from `pi-extension/`: `corepack pnpm typecheck` passed; targeted `reachability_contract.test.ts` passed. Full `corepack pnpm test` was run but is not clean in this container due pre-existing UDS/cwd-lock/leader-election environment failures and unrelated current-head `extension.test.ts` session-gate expectations; touched reachability reconnect tests in `extension.test.ts` passed.
