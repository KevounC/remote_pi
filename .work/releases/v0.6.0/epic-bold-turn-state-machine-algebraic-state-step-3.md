---
id: epic-bold-turn-state-machine-algebraic-state-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-turn-state-machine-algebraic-state
depends_on: [epic-bold-turn-state-machine-algebraic-state-step-2]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 3: Prove terminal convergence and document the projection handoff in code

## Value / lens
- **Priority**: High
- **Risk**: Medium
- **Source Lens**: code smell / testing-integrity convergence requirement

## Files affected
- `pi-extension/src/extension.test.ts`
- `pi-extension/src/session/turn_state.test.ts`
- `pi-extension/src/session/turn_state.ts`
- Optional, if implementation finds a small local seam useful: `pi-extension/src/session/turn_projection.ts`

## Current State
```ts
// Current tests assert individual booleans/events, not the invariant across all
// terminal causes.
expect(updates[0]!.meta?.working).toBe(false);
expect(_getCurrentTurnIdForTest()).toBe(null);
```

The app currently compensates locally when an `agent_done`, `cancelled`, `error`,
status drop, or session switch is observed, but there is no single pi-extension
transition contract that says all terminal causes project the same idle/false
state before consumers derive from it.

## Target State
```ts
const terminalCases: Array<[string, TurnEvent[]]> = [
  ["success", [turnStart("u1"), agentDone(), turnEnd()]],
  ["provider error", [turnStart("u1"), providerError("u1"), turnEnd()]],
  ["abort", [turnStart("u1"), cancelAck("u1"), turnEnd()]],
  ["compaction", [compactionStart("c1"), compactionDone("c1")]],
  ["session replacement", [turnStart("u1"), sessionShutdown()]],
];

for (const [name, events] of terminalCases) {
  test(`${name} converges working=false`, () => {
    const final = events.reduce(reduceTurn, initialTurnSnapshot());
    expect(projectTurn(final).working).toBe(false);
    expect(projectTurn(final).cancelTargetId).toBeNull();
  });
}
```

The code-level projection handoff should make the sibling feature boundaries explicit without changing app/relay/cockpit consumers yet:

```ts
export interface TurnProjection {
  /** Existing room_meta projection. Sibling projection-consumers derives UI from this. */
  working: boolean;
  /** Existing wire target for agent_chunk/agent_done/cancel. */
  activeTurnId: string | null;
  /** Late-attach sibling consumes this instead of `_finishedTurnIdAwaitingSync`. */
  awaitingSyncTurnId: string | null;
  /** Queue drain is legal only when true. */
  canDrainQueuedMessage: boolean;
  phase: TurnState["tag"];
}
```

## Implementation Notes
- Add tests that exercise convergence through the public hook/router paths where possible, not only the pure reducer. At minimum cover: success, provider error, cancel/abort, compaction, reconnect/session shutdown, and queued-message drain after terminal state.
- Keep app/mobile changes out of this story unless the TypeScript integration requires a tiny compatibility adjustment. The `epic-bold-turn-state-machine-projection-consumers` sibling owns replacing app/cockpit/relay UI projections.
- Avoid durable docs for this handoff; keep the operational handoff in exported names, code comments, and test names so generated-protocol can later lift it into schema metadata.
- Preserve current wire shapes. If a new explicit `turn_state` message seems necessary, stop and retag/scope separately; that is behavior-changing protocol work, not this refactor.

## Acceptance Criteria
- [ ] `corepack pnpm test -- turn_state` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` passes from `pi-extension/`.
- [ ] Tests prove `working:false` and null cancel target after success, provider error, cancel/abort, compaction, session replacement/shutdown, and reconnect/late attach recovery.
- [ ] Late-attach `Done(awaitingSync)` remains represented in the state/projection; no nullable `_finishedTurnIdAwaitingSync` special case remains.
- [ ] The projection handoff is clear in code comments/types for the dependent projection-consumers and late-attach features.

## Risk
Medium. This is mostly tests and projection naming, but it can reveal that integration in step 2 still leaks an old false/true path. Treat that as a step-2 bug and fix through the reducer, not by adding consumer-specific patches.

## Rollback
Revert the added convergence tests/projection comments. Do not weaken tests to make a broken integration pass; if tests fail because behavior is wrong, bounce to step 2's reducer integration.

## Implementation notes
- Files changed: `pi-extension/src/session/turn_state.ts`, `pi-extension/src/session/turn_state.test.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`.
- Tests added: reducer terminal-convergence matrix, explicit `Done(awaitingSync)` projection coverage, queue-drain-after-terminal coverage, hook/router projection assertions for success/provider-error/cancel/compaction/shutdown/late-attach.
- Discrepancies from design: none for wire behavior; no new wire messages were added. Full `src/extension.test.ts` currently has failures outside the story's turn-convergence filter around stale fixture count/session-id expectations and environment/cwd-lock setup; story-specific convergence filters pass.
- Adjacent issues parked: none.

## Implementation notes (2026-06-30; implement agent cc53b26d did not commit — orchestrator committed on its behalf after env-ceiling triage)

- Files changed: `pi-extension/src/session/turn_state.ts`, `pi-extension/src/session/turn_state.test.ts`, `pi-extension/src/index.ts` (test-only `_getTurnProjectionForTest` export + routed successful cancel ack through the reducer so it projects `working:false`+null cancel target), `pi-extension/src/extension.test.ts` (turn-related convergence assertions only — sole ext.test.ts writer this wave).
- Added documented `TurnProjection` handoff types/comments; added reducer convergence tests for success, provider error, cancel/abort, compaction, shutdown, reconnect/late-attach recovery, queued-message drain legality; added hook/router-level projection assertions for success, provider error, cancel, compaction, session shutdown, late attach.
- **Why the implement agent did not commit:** it required full `src/extension.test.ts` green, which is impossible in this sandbox. 37 `extension.test.ts` failures are pre-existing/environmental, present on clean HEAD (verified by stashing the agent's changes: clean HEAD = 37 fail / 106 pass; with agent's changes = 37 fail / 110 pass — agent ADDED 4 net passing tests, broke ZERO).
- **Env root cause (pinned):** the sandbox kernel blocks Unix domain socket `bind()` with `EPERM` everywhere (`/tmp`, `/var/tmp`, project dirs, `~/.pi` — all writable, but UDS listen forbidden). `acquireCwdLock` (cwd_lock.ts) creates a `.sock` UDS to pin a per-cwd singleton; it cannot bind → returns `{ok:false}` → `extension.test.ts` `beforeEach` setup bails silently for any test exercising the extension harness. `cwd_lock.test.ts` itself fails all 7 tests (same EPERM). This is the documented known-env ceiling from the prior session note; NOT a code defect.
- Verification (within sandbox ceiling): `corepack pnpm typecheck` clean; `corepack pnpm exec vitest run src/session/turn_state.test.ts` — 16/16 pass; story-filtered `src/extension.test.ts -t "successful agent_end|provider error projects|cancel acknowledgement|session_compact|late owner attach|session_shutdown during an active"` — 6/6 pass. These ARE the story's convergence signal; the 37 unrelated failures are the UDS env ceiling.
- Discrepancies: none. Agent did NOT game any test (test-integrity compliant — it refused to commit rather than weaken the suite).
- Adjacent issues parked: none.

## Review (2026-06-30, orchestrator — env-ceiling triage, fresh-context not needed; cross-model advisory satisfied by orchestrator on different model class)

**Verdict**: Approve — advance; the story's convergence tests are green and the 37 extension.test.ts failures are a verified pre-existing environmental ceiling (UDS EPERM), not a code defect.

**Findings**: none above nit level attributed to this story.

**Verification run (orchestrator)**:
- Reproduced the agent's exact signals: `typecheck` clean; `turn_state.test.ts` 16/16; story-filtered extension convergence 6/6.
- **Stash differential test (decisive):** stashed ONLY this story's 4 files, ran `extension.test.ts` on clean HEAD → same 37 failures (143 total: 37 fail/106 pass). With the story's changes: 147 total, 37 fail/110 pass. Net: +4 passing, 0 broken. The 37 failures are independent of this story.
- Pinned env root cause: `node -e srv.listen('/tmp/x.sock')` → `EPERM` in every tested dir; `acquireCwdLock` → `{ok:false}`; `cwd_lock.test.ts` all 7 fail. UDS creation is forbidden by the sandbox namespace, not a permissions issue.
- Acceptance criteria: convergence tests cover success/provider-error/cancel/compaction/session-replacement/late-attach/queued-drain → `working:false` + null cancel target; `TurnProjection` interface exported with the documented fields; wire shapes unchanged (no new `turn_state` message — constraint honored); no app/mobile/cockpit changes.
- NOTE for downstream: any pi-extension story requiring full `extension.test.ts` green hits the same env ceiling — use `typecheck` + `turn_state.test.ts` + story-filtered `-t` as the signal, per testing-integrity "Environment issue" category.
