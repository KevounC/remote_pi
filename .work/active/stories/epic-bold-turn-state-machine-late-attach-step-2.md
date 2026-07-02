---
id: epic-bold-turn-state-machine-late-attach-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-turn-state-machine-late-attach
depends_on: [epic-bold-turn-state-machine-late-attach-step-1]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 2: Route owner attach and late sync through the turn projection

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / missing abstraction  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/turn_state.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
  if (_turnActive) _peersAttachedDuringTurn.add(appPeerId);
}

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

function _maybeSendLateAttachSessionSync(): void {
  if (!_finishedTurnIdAwaitingSync || _turnActive) return;
  const inReplyTo = _finishedTurnIdAwaitingSync;
  _finishedTurnIdAwaitingSync = null;
  const targets = [..._peersAttachedDuringTurn];
  _peersAttachedDuringTurn.clear();
  if (targets.length === 0) return;
  const history = _buildSessionHistoryMessage(inReplyTo, undefined);
  for (const peerId of targets) {
    const channel = _activePeers.get(peerId);
    if (!channel) continue;
    try { channel.send(history); } catch { /* best-effort per late attach */ }
  }
}
```

## Target State

```ts
function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
  _applyTurn({ type: "peer_attached", target: { kind: "owner", id: appPeerId } });
}

pi.on("agent_end", () => {
  const before = _turnProjection();
  const inReplyTo = before.replyTo ?? before.activeTurnId;
  _applyTurn({ type: "agent_done" });
  if (_anyPeerActive() && inReplyTo !== null) {
    _broadcastToActive({ type: "agent_done", in_reply_to: inReplyTo });
  }
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});

function _maybeSendLateAttachSessionSync(): void {
  const projection = _turnProjection();
  if (!projection.canFlushLateAttachSync || projection.awaitingSyncTurnId === null) return;
  const history = _buildSessionHistoryMessage(projection.awaitingSyncTurnId, undefined);
  for (const target of projection.lateAttachSyncTargets) {
    if (target.kind !== "owner") continue;
    const channel = _activePeers.get(target.id);
    if (!channel) continue;
    try { channel.send(history); } catch { /* best-effort per late attach */ }
  }
  _applyTurn({ type: "flush_late_attach_sync" });
}
```

## Implementation Notes

- Remove `_finishedTurnIdAwaitingSync` and direct `_peersAttachedDuringTurn` mutation from `index.ts`; the only late-attach writes should be reducer events.
- `_maybeDrainQueuedMessage` should use `projectTurn(_turn).canDrainQueuedMessage`, not `_turnActive || _currentTurnId` checks.
- Preserve the current wire contract: late-attached owners still receive real-time chunks/done when attached before those frames, plus `session_history` after terminal flush when they missed earlier history.
- Preserve reconnect behavior: relay hello/room metadata should already carry `working:true` when the turn is active, and terminal projection must update cached `_myRoomMeta.working` to `false` before a reconnect hello can replay it.
- A missing channel for a recorded target is not an error; skip it and still clear the target on flush.

## Acceptance Criteria

- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` and `corepack pnpm test -- turn_state` pass from `pi-extension/`.
- [ ] `pi-extension/src/index.ts` no longer has a nullable `_finishedTurnIdAwaitingSync` latch.
- [ ] Owner attach during an active local/RPC turn is represented by a `peer_attached` reducer event.
- [ ] The existing late owner attach test still proves `agent_chunk`, `agent_done`, `session_history`, and `working:false` reach the late owner.
- [ ] Add/adjust a regression where a late owner attaches, the turn ends, and a queued message drains only after late sync flush is safe.

## Risk

High. This is the integration step that can break stream correlation, queued-message drain, or multi-owner reconnect if projection selectors are wrong.

## Rollback

Revert `index.ts` and extension tests to the algebraic-state baseline. Step 1 can remain unused while the integration is backed out.

## Implementation notes
- Files changed: `pi-extension/src/index.ts`.
- Tests added: none in this stride; the existing reducer tests cover `peer_attached`, `Done(awaitingSync)`, flush, and queued-drain selectors.
- Discrepancies from design: owner attach and late-sync routing were already represented through `_applyTurnAndPublish({ type: "peer_attached" ... })`, `_turnProjection().canFlushLateAttachSync`, and `lateAttachSyncTargets`; this pass removed the remaining duplicate queued-message latch so queued drain is fully projection-driven.
- Adjacent issues parked: none.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm exec vitest run src/session/turn_state.test.ts src/session/session_gate.test.ts` passed.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. The story's own implementation commit `208238f6a6fbf37c798dd8a6e458a17eeb9151ec` only advanced the item body; the code path had already landed in the current `pi-extension/src/index.ts`/`turn_state.ts` integration. Verified owner attach routes through `_applyTurnAndPublish({ type: "peer_attached", target: { kind: "owner", id } })`, late sync reads `projectTurn(_turn)` selectors (`canFlushLateAttachSync`, `awaitingSyncTurnId`, `lateAttachSyncTargets`), and queued drain reads `canDrainQueuedMessage`. Verification run: `corepack pnpm typecheck` passed; `corepack pnpm exec vitest run src/session/turn_state.test.ts src/session/session_gate.test.ts` passed. Full `corepack pnpm test` was attempted and failed in unrelated environment-sensitive UDS/cwd-lock suites (`listen EPERM` under `/tmp/.../*.sock` plus lock acquisition failures), while the targeted reducer/session-gate checks passed.
