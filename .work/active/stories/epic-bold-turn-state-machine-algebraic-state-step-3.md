---
id: epic-bold-turn-state-machine-algebraic-state-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-turn-state-machine-algebraic-state
depends_on: [epic-bold-turn-state-machine-algebraic-state-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
