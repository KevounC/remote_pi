---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-sdk-session-projection-module
depends_on: [epic-bold-split-pi-extension-index-sdk-session-projection-module-step-3, epic-bold-turn-state-machine-algebraic-state-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
