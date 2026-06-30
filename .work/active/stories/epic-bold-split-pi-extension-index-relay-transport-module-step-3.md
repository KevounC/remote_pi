---
id: epic-bold-split-pi-extension-index-relay-transport-module-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-relay-transport-module
depends_on: [epic-bold-split-pi-extension-index-relay-transport-module-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 3: Centralize relay control frames and room-meta updates behind RelayTransportPort

## Current State
Room metadata updates are scattered through `index.ts` and call the relay
directly:

```ts
function _publishWorking(working: boolean): void {
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, working };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { working } });
  }
}
```

Similar direct `sendControl` calls exist for model, thinking, and `session_id`.
The low-level `RelayClient.sendControl()` is already best-effort/no-op when the
socket is closed, but callers still need to know about `_relay` and `_myRoomId`.

## Target State
Room metadata remains cached at the session/projection boundary, while relay
control-frame emission goes through the relay transport port:

```ts
function _publishWorking(working: boolean): void {
  _sessionProjection.updateRoomMeta({ working });
  ports.relay.sendRoomMeta({ working });
}

ports.relay.sendRoomMeta({ model: modelName });
ports.relay.sendRoomMeta({ thinking: level });
ports.relay.sendRoomMeta({ session_id: sessionId });
```

Inside the module:

```ts
sendRoomMeta(patch: Partial<RoomMeta> & { working?: boolean; thinking?: ThinkingLevel }): void {
  if (!roomId) return;
  roomMeta = { ...roomMeta, ...patch };
  relay?.sendControl({ type: "room_meta_update", room_id: roomId, meta: patch });
}
```

## Notes
- Preserve the current best-effort semantics: closed relay means dropped control frame, not thrown callback.
- Preserve cached room meta so the next reconnect `hello` carries the latest model/thinking/working/session fields.
- Do not add new room-meta fields or change wire casing.
- Keep app debounce behavior untouched; extension still publishes raw working transitions.

## Acceptance Criteria
- [ ] All `room_meta_update` sends in `index.ts` route through `RelayTransportPort.sendRoomMeta()` or an equivalent single relay-control method.
- [ ] Reconnect still replays the latest room meta after model/thinking/session/working changes.
- [ ] Existing tests for model select, turn start/end, compaction working=false, and reconnect-after-model-select still pass.
- [ ] No control-frame caller catches `relay: not connected`; the transport keeps the current no-throw policy.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "model meta|working|compaction|reconnect after model_select"` passes, plus `corepack pnpm typecheck`.

## Risk
Medium. The risk is stale room-meta snapshots on reconnect, not immediate frame
delivery.

## Rollback
Restore the direct `_relay.sendControl({ type: "room_meta_update", ... })` call
sites in `index.ts` and keep the transport module's `sendRoomMeta` unused until a
later retry.

## Implementation
- Confirmed `index.ts` room-meta publishers (`model`, `thinking`, `session_id`, and `working`) route through `_publishRoomMetaPatch()` into `RelayTransportPort.sendRoomMeta()`; there are no direct `sendControl` room-meta call sites left in `index.ts`.
- Preserved best-effort behavior: closed relay control frames do not throw from SDK callbacks, and the relay transport cache supplies the latest room meta on the next reconnect hello.
- Added targeted coverage for a closed-relay model/working update before reconnect, proving reconnect replays `model: "gpt-4o"` and `working: false` from the cached room meta.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; targeted Vitest command passed with 1 file, 19 passed, 131 skipped, 0 failed.
- Observed only the known harmless `/home/agent/.npmrc` EACCES warning; no false-failure suite pattern was hit in targeted verification.

## Review

Approved (2026-06-30). Independently re-ran: `corepack pnpm typecheck` clean;
`corepack pnpm build` clean; **full pi-ext suite 652 passed | 3 skipped | 0 failed
(44 files)** — fully green (up from 651 — the agent's new reconnect-replay tests).

Commit `e66765a` scoped to pi-ext only (relay_transport.ts sendRoomMeta +
extension.test.ts +42 reconnect coverage + story .md); collision guard held.
Centralization verified: no direct `room_meta_update` sends remain in index.ts
(grep count 0); all route through `RelayTransportPort.sendRoomMeta()`. Best-effort
no-throw policy preserved (closed relay = dropped frame, no thrown callback).
Cache-replay preserved: `sendRoomMeta` updates cached `roomMeta` + best-effort
`relay?.sendControl(...)`, so reconnect hello carries latest model/thinking/
working/session. Targeted reconnect tests (19 passed, 0 failed) prove the
closed-relay-cache-then-replay path.
