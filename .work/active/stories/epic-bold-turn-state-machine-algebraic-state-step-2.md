---
id: epic-bold-turn-state-machine-algebraic-state-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-turn-state-machine-algebraic-state
depends_on: [epic-bold-turn-state-machine-algebraic-state-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Replace pi-extension turn booleans with the reducer

## Value / lens
- **Priority**: High
- **Risk**: High
- **Source Lens**: code smell / missing abstraction

## Files affected
- `pi-extension/src/index.ts`
- `pi-extension/src/session/turn_state.ts`
- `pi-extension/src/transport/relay_client.ts`
- `pi-extension/src/extension.test.ts`

## Current State
```ts
// pi-extension/src/index.ts
let _currentTurnId: string | null = null;
let _turnActive = false;
let _finishedTurnIdAwaitingSync: string | null = null;
const _peersAttachedDuringTurn = new Set<string>();
let _queuedMessage: QueuedMessage | null = null;

pi.on("agent_end", () => {
  if (!_currentTurnId) return;
  const finishedTurnId = _currentTurnId;
  _broadcastToActive({ type: "agent_done", in_reply_to: finishedTurnId });
  _currentTurnId = null;
  _finishedTurnIdAwaitingSync = finishedTurnId;
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});

pi.on("turn_start", (_event, ctx) => {
  _turnActive = true;
  _finishedTurnIdAwaitingSync = null;
  _peersAttachedDuringTurn.clear();
  if (_currentTurnId === null) _currentTurnId = `local_${randomUUID()}`;
  _publishWorking(true);
});

pi.on("turn_end", () => {
  _turnActive = false;
  _publishWorking(false);
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});
```

`relay_client.ts` also carries stale metadata types:

```ts
export interface RoomMeta { name: string; cwd: string; model?: string; }
export interface RoomMetaUpdateFrame {
  type: "room_meta_update";
  room_id: string;
  meta: { model?: string };
}
```

## Target State
```ts
let _turn = initialTurnSnapshot();

function _applyTurn(event: TurnEvent): TurnProjection {
  const before = projectTurn(_turn);
  _turn = reduceTurn(_turn, event);
  const after = projectTurn(_turn);
  if (before.working !== after.working) _publishWorking(after.working);
  return after;
}

pi.on("turn_start", (_event, ctx) => {
  _applyTurn({ type: "turn_start", fallbackTurnId: `local_${randomUUID()}` });
  _hydrateModelIfNeeded(ctx);
});

pi.on("message_update", (event) => {
  const projection = _applyTurn({ type: "agent_chunk" });
  if (!_anyPeerActive() || !projection.activeTurnId) return;
  _broadcastToActive({ type: "agent_chunk", in_reply_to: projection.activeTurnId, delta });
});

pi.on("agent_end", () => {
  const projection = _applyTurn({ type: "agent_done" });
  if (projection.doneTurnId && _anyPeerActive()) {
    _broadcastToActive({ type: "agent_done", in_reply_to: projection.doneTurnId });
  }
  _flushLateAttachAndQueuedFromProjection(projection);
});
```

Metadata types become aligned with the live room metadata surface:

```ts
export interface RoomMeta {
  name: string;
  cwd: string;
  model?: string;
  thinking?: ThinkingLevel;
  working?: boolean;
}
export interface RoomMetaUpdateFrame {
  type: "room_meta_update";
  room_id: string;
  meta: { model?: string; thinking?: ThinkingLevel; working?: boolean };
}
```

## Implementation Notes
- Keep wire behavior stable: continue emitting the existing `user_message`, `agent_chunk`, `agent_done`, `tool_request`, `tool_result`, `error`, `cancelled`, `queued_message_state`, `session_history`, `compaction`, and `room_meta_update` messages.
- Replace `_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`, `_peersAttachedDuringTurn`, and `_queuedMessage` with the reducer snapshot and selectors. If a temporary adapter is needed, keep it private and delete it before the story is complete.
- Centralize all `working` publication through `projectTurn`. It is acceptable to emit duplicate `working:false` updates when terminal hooks race; duplicate false is idempotent and safer than a stuck true.
- Preserve steering semantics: a `steer` message while active must not replace the active reply target; a reconnecting app with no current id may seed a fallback id just as today.
- Preserve late-attach semantics: peers attached during an SDK turn receive a final `session_history` once terminal state is safe to flush.
- Preserve queued-message semantics: queue drains only after the active turn is terminal/idle, not merely after `agent_done` if late-attach sync is still pending.

## Acceptance Criteria
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` (or the nearest Vitest filter) passes from `pi-extension/`.
- [ ] Existing extension tests for working true/false, compaction, late owner attach, steering, and queued messages still pass.
- [ ] `pi-extension/src/index.ts` has no remaining module-level `_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`, `_peersAttachedDuringTurn`, or `_queuedMessage` globals.
- [ ] All room metadata TypeScript types include the live `thinking` and `working` fields rather than relying on structural excess-property tolerance.

## Risk
High. This touches the pi-extension's central lifecycle hooks and can regress streaming, cancel, late attach, or queued prompt drain. Keep changes mechanical and use the reducer tests from step 1 as the guardrail.

## Rollback
Revert `index.ts`, `relay_client.ts`, and the related tests to the previous boolean-based implementation. The pure reducer from step 1 can remain unused if integration must be backed out independently.

## Implementation notes
- Files changed: `pi-extension/src/index.ts`.
- Tests added: none; existing reducer and session-gate tests exercise the projection paths touched here.
- Discrepancies from design: the hook integration and `RoomMeta` typing had already landed before this stride; this pass completed the remaining queue migration by removing the duplicate `_queuedMessage` global and deriving queued state/drain from `projectTurn(_turn)`.
- Adjacent issues parked: none.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm exec vitest run src/session/turn_state.test.ts src/session/session_gate.test.ts` passed.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Inspected implementation commit `8c9a1f80b4683b4d93d0263ef6a016992230a6e3` and current `pi-extension/src/index.ts` / `src/session/turn_state.ts`. The remaining duplicate `_queuedMessage` global is gone; queued state is projected from `TurnSnapshot`, and direct greps found no module-level `_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`, `_peersAttachedDuringTurn`, or `_queuedMessage` globals in `index.ts` (only projected helper names remain). Verification run: `corepack pnpm typecheck` passed; `corepack pnpm exec vitest run src/session/turn_state.test.ts src/session/session_gate.test.ts` passed. Full `corepack pnpm test` was also attempted and failed in unrelated environment-sensitive UDS/cwd-lock suites (`listen EPERM` under `/tmp/.../*.sock` plus lock acquisition failures), while the targeted turn reducer/session-gate checks passed.
