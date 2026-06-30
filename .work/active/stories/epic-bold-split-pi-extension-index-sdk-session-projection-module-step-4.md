---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-sdk-session-projection-module
depends_on: [epic-bold-split-pi-extension-index-sdk-session-projection-module-step-3, epic-bold-turn-state-machine-algebraic-state-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Move turn, queue, and late-attach state into the projection module

## Current State
```ts
// pi-extension/src/index.ts
let _currentTurnId: string | null = null;
let _turnActive = false;
let _finishedTurnIdAwaitingSync: string | null = null;
const _peersAttachedDuringTurn = new Set<string>();
let _queuedMessage: QueuedMessage | null = null;

function _maybeDrainQueuedMessage(): void {
  if (!_queuedMessage || _turnActive || _currentTurnId !== null) return;
  const queued = _queuedMessage;
  _queuedMessage = null;
  _broadcastQueuedMessageState();
  void _deliverUserMessage({ type: "user_message", id: queued.id, text: queued.text }, null, "normal");
}
```

The turn lifecycle, queued-message state, late-attach sync, and room-meta `working` projection are nullable globals in `index.ts`.

## Target State
```ts
// pi-extension/src/session/sdk_session_projection.ts
export class SdkSessionProjection implements SdkSessionProjectionPort {
  private turn = initialTurnSnapshot();

  onPiInput(event: { text: string; source?: string }): void {
    if (event.source === "extension") return;
    const projection = this.applyTurn({ type: "local_input", fallbackTurnId: `local_${this.randomId()}` });
    this.opts.outputs.broadcast({ type: "user_input", id: projection.activeTurnId!, text: event.text });
  }

  private applyTurn(event: TurnEvent): TurnProjection {
    const before = projectTurn(this.turn);
    this.turn = reduceTurn(this.turn, event);
    const after = projectTurn(this.turn);
    if (before.working !== after.working) this.opts.outputs.publishRoomMeta({ working: after.working });
    return after;
  }
}
```

## Implementation Notes
- This story depends on `epic-bold-turn-state-machine-algebraic-state-step-1`; consume the pure reducer rather than inventing a second turn model.
- Preserve current wire behavior: do not add a new turn-state message. Existing `user_input`, `agent_chunk`, `agent_done`, `tool_request`, `tool_result`, `compaction`, `queued_message_state`, and `session_history` messages remain the app contract.
- Late-attach peers are selected through injected owner outputs (`lateAttachTargets`, `activeOwnerIds`) rather than `_activePeers` imports.
- Queue drain uses reducer projection (`canDrainQueuedMessage`) rather than `_turnActive`/`_currentTurnId` checks.
- `working` is derived from reducer projection and published through the room-meta output.

## Acceptance Criteria
- [ ] `_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`, `_peersAttachedDuringTurn`, and `_queuedMessage` are removed from `index.ts` and owned by `SdkSessionProjection`/`turn_state`.
- [ ] App prompts, steer behavior, local terminal input, agent chunks/done, tool visibility, compaction marker replay, queued prompt set/clear/drain, and late-owner attach behavior is preserved.
- [ ] Tests prove `working:false` convergence after success, provider error, cancel/abort, compaction, session replacement/shutdown, relay reconnect, and late attach recovery.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test -- turn_state`, and targeted `corepack pnpm test -- extension` pass from `pi-extension/`.

## Risk
High. Several formerly-independent globals become one reducer-backed snapshot; tests must prove terminal convergence and late-attach behavior.

## Rollback
Move turn/queue/late-attach fields and helper functions back into `index.ts`; keep the reducer module from the turn-state feature if already landed.

## Implementation
- Files changed: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/index.ts`.
- Turn/queue/late-attach migration: `SdkSessionProjection` now owns the reducer snapshot (`private turn = initialTurnSnapshot()`), reducer application, room-meta `working` publication, queued-message state projection/broadcast/drain, owner late-attach recording, late-attach session-history flush, and app-prompt seed/rollback. `index.ts` no longer imports reducer functions or stores the turn snapshot; it delegates through projection methods.
- Working convergence preserved for all seven required paths: success (`agent_end`/`turn_end`), provider error (`message_end stopReason:error`), cancel/abort (`cancel` route), compaction (`session_before_compact`/`session_compact`), session replacement/shutdown (`session_new` reset and `session_shutdown` teardown), relay reconnect (closed-relay turn-end updates are cached into reconnect `room_meta.working:false`), and late-attach recovery (late owner gets chunk/done/history, then projection returns idle).
- Tests: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; `corepack pnpm exec vitest run src/session/turn_state.test.ts` passed `16 passed`; `corepack pnpm exec vitest run src/extension.test.ts` reported `154 passed | 4 failed`.
- False-alarm observation: the four `extension.test.ts` failures match the documented environment/cwd-lock false-failure bucket, not the real turn/working/listener-count bucket: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, and `a second same-name agent joins as <name>#2 instead of being refused`.
- Discrepancies from design: hook bodies remain in `index.ts` for this step, but all moved mutable turn/queue/late-attach state is projection-owned and reducer-backed.
- Adjacent issues parked: none.

## Review

Approved (2026-06-30). Independently re-ran (clean state): `corepack pnpm typecheck`
clean; `corepack pnpm build` clean; `corepack pnpm exec vitest run src/session/
turn_state.test.ts` → 16 passed; **full pi-ext suite 660 passed | 3 skipped |
0 failed (44 files)** — fully green. The 4 failures the agent reported are genuinely
the environment-flake false-alarm signature (`after a clean reset`, `name-assigned`,
`rename:<name>`, same-name `#2`) — confirmed by clean orchestrator re-run (0 failures).
The agent CORRECTLY classified them by reading the actual test names (all 4 are the
mesh/cwd-lock environment bucket, not behavior assertions).

Migration verified: the 5 globals (`_currentTurnId`/`_turnActive`/
`_finishedTurnIdAwaitingSync`/`_peersAttachedDuringTurn`/`_queuedMessage`) removed
from index.ts (grep count 0) — now projection-owned reducer-backed snapshot.
Working:false convergence preserved for all 7 required paths (success, provider
error, cancel/abort, compaction, session replacement/shutdown, relay reconnect,
late-attach recovery) — 33 convergence-related extension tests pass (2× consistent).
Commit `fbed734` scoped to pi-ext only (sdk_session_projection.ts +110 +
index.ts -62); collision guard held.
