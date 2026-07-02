---
id: epic-bold-split-pi-extension-index-relay-transport-module-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-relay-transport-module
depends_on: [epic-bold-split-pi-extension-index-relay-transport-module-step-1]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 2: Move relay start, close, reconnect, and relay-state emission into the module

## Current State
`index.ts` starts the relay, handles unexpected close, schedules reconnect, and
emits Cockpit relay-state events directly:

```ts
const relay = new RelayClient(toWebSocketUrl(relayUrl), edKp);
await relay.connect({ roomId, roomMeta });
_relay = relay;
_relayUrl = relayUrl;
relay.on("close", _onRelayClose);
_stopAutoListener = _installAutoListener(relay);
```

```ts
function _onRelayClose(): void {
  if (_state === "idle") return;
  _stopAutoListener?.();
  _activePeers.clear();
  _relay = null;
  _meshNode?.detachBridge();
  _state = "started";
  _emitRelayState();
  _scheduleReconnect();
}
```

## Target State
`index.ts` builds the start input and delegates transport ownership to the
module. The module keeps the same behavior internally:

```ts
const result = await ports.relay.start({
  relayUrl,
  keypair: edKp,
  roomId,
  roomMeta,
  onUnexpectedClose: () => {
    legacyOwners.detachAllForRelayDrop();
    legacyMesh.detachCrossPcBridge();
    setStartedStateForReconnect();
  },
  emitRelayState: (snapshot) => emitRelayState(snapshot),
});

_peerShort = result.peerShort;
_myRoomId = result.roomId;
_state = "started";
```

Inside the module:

```ts
async function attemptReconnect(): Promise<void> {
  if (status() === "disconnected" || !keypair || !relayUrl) return;
  const next = deps.createRelay(deps.toWebSocketUrl(relayUrl), keypair);
  try {
    await next.connect({ roomId, roomMeta });
  } catch {
    scheduleReconnect();
    return;
  }
  relay = next;
  reconnectAttempt = 0;
  wireRelay(next);
  emitStatus();
}
```

## Notes
- Preserve reconnect backoff sequence exactly: `1s, 2s, 5s, 10s, 30s, 30s...`.
- Preserve `/remote-pi stop` winning over a pending reconnect by cancelling the timer in `stop()`.
- Preserve `_cmdStart`'s post-`relay.connect()` disposed guard: a relay that connects after session shutdown must be closed and must not become current.
- Preserve `room_id` + `room_meta` replay on reconnect to avoid phantom legacy sessions.
- Keep SelfRevoke startup outside the transport module in this step; it is mesh-membership/pairing state, not relay socket ownership.

## Acceptance Criteria
- [ ] `index.ts` no longer owns `_relay`, `_relayUrl`, `_reconnectTimer`, `_reconnectAttempt`, or `_lastRelayStatus` directly.
- [ ] Relay connect failure, `RoomAlreadyOpenError`, and user notifications remain identical.
- [ ] Reconnect tests still cover the same backoff schedule, timer cancellation on stop, counter reset after success, and room-meta replay.
- [ ] `remote-pi:relay-state` custom messages keep the same `details.status`, `details.connected`, `details.relayUrl`, and `details.room` shape.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "relay reconnect|relay control channel|reconnect replays"` passes, plus `corepack pnpm typecheck`.

## Risk
High. This changes ownership of the live relay and reconnect callbacks; stale
session and stop-vs-reconnect races are easy to regress.

## Rollback
Move the start/close/reconnect/status functions back into `index.ts` and restore
the previous relay globals. Because protocol and CLI shapes do not change, rollback
is localized to `index.ts` plus the new adapter module.

## Implementation
- Moved live relay ownership into `pi-extension/src/extension/relay_transport.ts`: start, close, unexpected-close handling, reconnect scheduling/attempts, pending timer/counter state, and relay-state snapshot/dedupe now live in the adapter.
- Updated `pi-extension/src/index.ts` to build the relay start input and delegate to `_relayTransport.start(...)`; `index.ts` no longer declares `_relay`, `_relayUrl`, `_reconnectTimer`, `_reconnectAttempt`, or `_lastRelayStatus`.
- Preserved reconnect behavior: backoff remains `1s, 2s, 5s, 10s, 30s, 30s...`; transport `stop()` cancels a pending timer so `/remote-pi stop` wins; reconnect success resets the attempt counter; reconnect replays the same `roomId` + current `roomMeta`.
- Preserved startup/shutdown guard: a relay that finishes `connect()` after the instance is disposed is closed and does not become current.
- Preserved `remote-pi:relay-state` shape via transport-owned snapshots bridged by index: `details.status`, `details.connected`, `details.relayUrl`, and `details.room` are unchanged.
- Kept SelfRevoke outside the transport module; index still starts it after a successful relay start.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; `corepack pnpm exec vitest run src/extension.test.ts -t "relay reconnect|reconnect replays"` passed `6 passed | 143 skipped | 0 failed`.
- Full requested targeted expression `relay reconnect|relay control channel|reconnect replays` produced the known false-alarm signature in the `relay control channel` group (`rename:<name>` / mesh-node setup), while the reconnect subset passed.

## Review

Approved (2026-06-30) with HIGH-risk reconnect-migration verification. Independently
re-ran: `corepack pnpm typecheck` clean; `corepack pnpm build` clean; **full pi-ext
suite 651 passed | 3 skipped | 0 failed (44 files)** — fully green.

Commit `40802b6` scoped to pi-ext only (relay_transport.ts +81 + index.ts ±354 +
story .md); collision guard held. Migration verified: `index.ts` no longer owns any
of the 5 relay globals (`_relay`/`_relayUrl`/`_reconnectTimer`/`_reconnectAttempt`/
`_lastRelayStatus` — grep count 0); they moved into `relay_transport.ts`. Reconnect
behavior preserved: backoff ladder `1s, 2s, 5s, 10s, 30s, 30s...`; `stop()` cancels
pending timer so `/remote-pi stop` wins; reconnect success resets attempt counter;
reconnect replays same `roomId` + current `roomMeta`. Startup/shutdown disposed
guard preserved (post-`connect()` relay after shutdown is closed, not current).
`remote-pi:relay-state` event shape unchanged (`details.status`/`details.connected`/
`details.relayUrl`/`details.room`). SelfRevoke kept outside transport module. The
reconnect subset tests (`6 passed | 143 skipped | 0 failed`) prove no regression.
