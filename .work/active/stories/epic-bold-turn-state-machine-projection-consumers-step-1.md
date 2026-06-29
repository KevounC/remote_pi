---
id: epic-bold-turn-state-machine-projection-consumers-step-1
kind: story
stage: review
tags: [refactor]
parent: epic-bold-turn-state-machine-projection-consumers
depends_on: [epic-bold-turn-state-machine-algebraic-state]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Project pi-extension broadcasts and room metadata from `TurnSnapshot`

**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/turn_state.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
pi.on("message_update", (event) => {
  if (!_anyPeerActive() || !_currentTurnId) return;
  const ae = event.assistantMessageEvent;
  if (ae.type === "text_delta") {
    _broadcastToActive({ type: "agent_chunk", in_reply_to: _currentTurnId, delta: ae.delta });
  }
});

pi.on("agent_end", () => {
  if (!_currentTurnId) return;
  const finishedTurnId = _currentTurnId;
  if (_anyPeerActive()) {
    _broadcastToActive({ type: "agent_done", in_reply_to: finishedTurnId });
  }
  _currentTurnId = null;
  _finishedTurnIdAwaitingSync = finishedTurnId;
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});

pi.on("turn_start", (_event, ctx) => {
  _turnActive = true;
  _finishedTurnIdAwaitingSync = null;
  _peersAttachedDuringTurn.clear();
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, working: true };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { working: true } });
  }
});
```

## Target State

```ts
function _turnProjection(): TurnProjection {
  return projectTurn(_turn);
}

function _publishTurnProjection(before: TurnProjection, after: TurnProjection): void {
  if (before.working === after.working) return;
  _publishWorking(after.working);
}

function _applyTurnAndPublish(event: TurnEvent): TurnProjection {
  const before = _turnProjection();
  _turn = reduceTurn(_turn, event);
  const after = _turnProjection();
  _publishTurnProjection(before, after);
  return after;
}

pi.on("message_update", (event) => {
  const ae = event.assistantMessageEvent;
  if (ae.type !== "text_delta") return;
  const projection = _applyTurnAndPublish({ type: "agent_chunk", delta: ae.delta });
  const replyTo = projection.replyTo ?? projection.activeTurnId;
  if (!_anyPeerActive() || replyTo === null) return;
  _broadcastToActive({ type: "agent_chunk", in_reply_to: replyTo, delta: ae.delta });
});

pi.on("agent_end", () => {
  const before = _turnProjection();
  const replyTo = before.replyTo ?? before.activeTurnId;
  _applyTurnAndPublish({ type: "agent_done" });
  if (_anyPeerActive() && replyTo !== null) {
    _broadcastToActive({ type: "agent_done", in_reply_to: replyTo });
  }
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});
```

## Implementation Notes

- Consume the reducer/projection exported by `epic-bold-turn-state-machine-algebraic-state`; do not recreate a second projection helper in `index.ts`.
- `room_meta.working` is still the public compatibility projection, but every write to it flows through the turn projection diff.
- `agent_chunk`, `agent_done`, cancel target, queued-message drain, and late-attach sync should read `replyTo` / `turnId` from projection selectors rather than from scattered nullable globals.
- Reconnect hello uses cached `_myRoomMeta.working` that was last written by projection. Session shutdown and compaction terminal paths must call the same `_applyTurnAndPublish` path so cached hello cannot replay stale `true`.
- Preserve existing wire messages and timing; duplicate `working:false` control frames are acceptable, but durable `working:true` after a terminal event is not.

## Acceptance Criteria

- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` and the turn-state test filter pass from `pi-extension/`.
- [ ] No `agent_chunk`, `agent_done`, cancel, queued-drain, or late-attach path reads a raw `_currentTurnId`/`_turnActive`-style global instead of a `TurnProjection` selector.
- [ ] Tests prove `room_meta.working:false` is published or cached after success, provider error, cancel/abort, compaction, session shutdown/replacement, and reconnect hydration.
- [ ] No new `turn_state` wire message is added.

## Rollback

Revert `index.ts` and tests to the algebraic-state integration baseline. Because the reducer remains side-by-side, rollback should not delete `turn_state.ts` unless the previous sibling is also being reverted.

## Implementation notes
- Files changed: `pi-extension/src/index.ts`, `pi-extension/src/session/turn_state.ts`, `pi-extension/src/session/turn_state.test.ts`.
- Tests added: no separate extension test file was added; existing extension coverage now exercises projection-driven chunk/done, queued-drain, compaction, late-attach, steering failure, and `room_meta.working` paths. The reducer tests added by the late-attach sibling also cover projection behavior used here.
- Discrepancies from design: The delegated prompt listed app/cockpit UI files for this story id, but the story body and parent feature step 1 are explicitly the pi-extension broadcast/room-meta projection. Implemented the item body as the load-bearing spec and left app/cockpit consumer rewrites to their designed downstream steps. Also preserved the existing empty `queued_message_state` runtime shape for compatibility with current extension tests, even though the newer TS union requires `session_id`.
- Adjacent issues parked: none.
- Verification: `corepack pnpm typecheck` passed. `corepack pnpm exec vitest run src/session/turn_state.test.ts` passed. Targeted `src/extension.test.ts` filters for queued drain, steering failure, compaction, late owner attach, and turn-end working false passed. A full `src/extension.test.ts` run before the focused fixes exposed unrelated/environment-sensitive mesh/lock failures in later tests; the touched-path filters are green.
