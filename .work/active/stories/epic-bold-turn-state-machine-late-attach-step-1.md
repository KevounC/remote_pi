---
id: epic-bold-turn-state-machine-late-attach-step-1
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-turn-state-machine-late-attach
depends_on: [epic-bold-turn-state-machine-algebraic-state]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Put late-attach collection into `TurnSnapshot`

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / code smell  
**Files**: `pi-extension/src/session/turn_state.ts`, `pi-extension/src/session/turn_state.test.ts`

## Current State

```ts
// pi-extension/src/index.ts
let _finishedTurnIdAwaitingSync: string | null = null;
const _peersAttachedDuringTurn = new Set<string>();

function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
  if (_turnActive) _peersAttachedDuringTurn.add(appPeerId);
}
```

Late-attach is encoded outside the turn reducer as a boolean/set/string cluster.

## Target State

```ts
export type LateAttachKind = "owner" | "mesh_bridge";
export interface LateAttachTarget {
  kind: LateAttachKind;
  id: string;
}

export type TurnEvent =
  | { type: "peer_attached"; target: LateAttachTarget }
  | { type: "agent_done" }
  | { type: "turn_end" }
  | { type: "flush_late_attach_sync" }
  | ExistingTurnEvent;

export interface TurnSnapshot {
  state: TurnState;
  queuedMessage: QueuedMessage | null;
  peersAttachedDuringTurn: ReadonlySet<string>;
}

export interface TurnProjection {
  working: boolean;
  replyTo: string | null;
  activeTurnId: string | null;
  awaitingSyncTurnId: string | null;
  lateAttachSyncTargets: readonly LateAttachTarget[];
  canFlushLateAttachSync: boolean;
  canDrainQueuedMessage: boolean;
}
```

Reducer behavior:

```ts
// peer_attached while active records the target.
Working/Streaming/AwaitingTool + peer_attached(owner) -> same state + target set

// agent_done makes the terminal state own the former nullable latch.
Working/Streaming/AwaitingTool + agent_done -> Done({ awaitingSync: true, turnId, targets })

// turn_end permits flushing without making working true.
Done(awaitingSync) + turn_end -> Done(awaitingSync, flushReady: true)

// explicit flush clears targets and allows idle/queue drain.
Done(awaitingSync) + flush_late_attach_sync -> Idle when no queued drain is pending

// shutdown clears all late targets and projects idle/error with working false.
Any + session_shutdown -> Error(reason: "session_shutdown") -> Idle
```

## Implementation Notes

- Build on the algebraic-state feature's `TurnState`, `TurnSnapshot`, `reduceTurn`, and `projectTurn`; do not introduce a second late-attach registry in `index.ts`.
- Keep `peersAttachedDuringTurn` in `TurnSnapshot` for the feature boundary promised by the sibling design, but expose it through projections/events rather than raw mutation.
- Treat late-attach targets as ids only. The reducer must not store channels, relay clients, brokers, or Pi SDK contexts.
- `Done(awaitingSync)` projects `working:false`; late sync is catch-up work, not an active turn.
- Duplicate `peer_attached` events for the same owner id should dedupe.

## Acceptance Criteria

- [ ] `corepack pnpm test -- turn_state` passes from `pi-extension/`.
- [ ] Reducer tests cover owner attach during `Working`, `Streaming`, and `AwaitingTool`.
- [ ] Reducer tests cover `agent_done -> Done(awaitingSync)` collecting late-attach targets with `working:false`.
- [ ] Reducer tests cover `turn_end + flush_late_attach_sync` clearing late targets and allowing queued-message drain.
- [ ] Reducer tests cover `session_shutdown` clearing late targets and projecting `working:false`.
- [ ] No reducer state stores concrete channels or lifecycle-owned resources.

## Risk

Medium. The risk is turning a narrow latch into a broader state that accidentally changes queue-drain or steering semantics.

## Rollback

Revert the added late-attach event/projection fields and tests from `turn_state.ts` / `turn_state.test.ts`. The algebraic-state reducer can remain without this extension.
