---
id: epic-bold-split-pi-extension-index-relay-transport-module-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-relay-transport-module
depends_on: [epic-bold-split-pi-extension-index-relay-transport-module-step-3]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 4: Move cross-PC relay bridge attach/detach ownership behind RelayTransportPort

## Current State
`index.ts` decides when the app relay can also carry cross-PC traffic:

```ts
function _attachBridgeIfReady(): void {
  if (!_meshNode || !_relay || !_relayUrl || !_cachedEd25519) return;
  void _meshNode
    .attachBridge({ relay: _relay, relayUrl: _relayUrl, keypair: _cachedEd25519 })
    .catch(() => { /* best-effort — UDS mesh works regardless */ });
}
```

It calls this from `_cmdStart`, `_attemptReconnect`, and `_cmdJoin`, while
`_goIdle` and `_onRelayClose` call `_meshNode?.detachBridge()`.

## Target State
The relay transport module owns the relay-side bridge attachment lifecycle. The
mesh module still owns the broker/remote router internals:

```ts
ports.relay.attachCrossPcBridge({
  meshNode: () => _meshNode,
  keypair: () => _cachedEd25519,
});
```

Inside the module:

```ts
async function attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void> {
  const meshNode = input.meshNode();
  const keypair = input.keypair();
  if (!meshNode || !relay || !relayUrl || !keypair) return;
  try {
    await meshNode.attachBridge({ relay, relayUrl, keypair });
  } catch {
    // best-effort: local UDS mesh works without cross-PC relay bridge
  }
}

function detachCrossPcBridge(): void {
  bridgeInput?.meshNode()?.detachBridge();
}
```

`start()` and successful reconnect call `attachCrossPcBridge()` after the relay
is current; `stop()` and unexpected relay close call `detachCrossPcBridge()`
before publishing disconnected/retrying state.

## Notes
- This is lifecycle ownership, not a behavior change. `MeshNode`, `BrokerRemote`, and `PiForwardClient` keep their current code and tests.
- Keep the injected-relay contract intact: `MeshNode` must not close a relay it did not create.
- Preserve best-effort failure handling; cross-PC bridge failure must not break app pairing or local UDS mesh.
- After awaits, re-check that the relay instance is still current before retaining bridge state.

## Acceptance Criteria
- [ ] `_attachBridgeIfReady` is removed from `index.ts` or reduced to a one-line compatibility call into `RelayTransportPort`.
- [ ] Relay start, relay reconnect success, local mesh join, relay close, and stop still attach/detach the bridge at the same points.
- [ ] Existing `session/mesh_node.ts`, `session/bridge.ts`, and `transport/pi_forward_client.ts` behavior is unchanged.
- [ ] Tests cover relay drop detaching cross-PC bridge and successful reconnect re-attaching it when a mesh leader exists.
- [ ] `corepack pnpm test -- src/extension.test.ts src/session/broker_remote.test.ts` passes, plus `corepack pnpm typecheck`.

## Risk
Medium. The bridge is best-effort, but a missed re-attach would silently disable
cross-PC agent routing after relay reconnect.

## Rollback
Restore `_attachBridgeIfReady()` in `index.ts` and direct `_meshNode?.detachBridge()`
calls in `_goIdle` / `_onRelayClose`; leave the transport module's bridge methods
unused.

## Implementation
- Moved cross-PC bridge lifecycle ownership into `pi-extension/src/extension/relay_transport.ts`: `attachCrossPcBridge()` now captures provider functions for the current mesh node/keypair, attaches only when relay + relay URL + keypair are current, preserves best-effort failure handling, and re-checks the relay instance after `await` before allowing the bridge state to stand.
- `RelayTransportPort.start()` and reconnect success re-attach after the relay is current; unexpected relay close and `stop()` detach before relay state publication. `_attachBridgeIfReady()` in `index.ts` is now a compatibility shim into the relay transport port, and direct `_meshNode?.detachBridge()` calls were removed from relay close/idle paths.
- `MeshNode`, `session/bridge.ts`, and `transport/pi_forward_client.ts` were not changed, preserving the injected-relay ownership contract.
- Added extension tests covering relay-drop detach and reconnect re-attach using a fake mesh node through `RelayTransportPort`.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; targeted bridge tests passed (`src/extension.test.ts --testNamePattern "relay drop detaches|successful reconnect re-attaches"`: 2 passed, 150 skipped); requested targeted suite reported `180 passed, 4 failed` across `src/extension.test.ts` + `src/session/broker_remote.test.ts`, where the failures match the known false-alarm mesh/cwd-lock/name-assigned/rename group described in the task.

## Review

Approved (2026-06-30) with bridge-lifecycle verification. Independently re-ran:
`corepack pnpm typecheck` clean; `corepack pnpm build` clean; **full pi-ext suite
654 passed | 3 skipped | 0 failed (44 files)** — fully green (up from 652 — the
agent's new bridge tests).

NOTE: the implementer CORRECTLY identified the false-failure pattern (7th
consecutive pi-ext agent to do so) — reported the targeted-suite "4 failed" as
"matching the known false-alarm mesh/cwd-lock/name-assigned/rename group."

Commit `ffa0711` scoped to pi-ext only (relay_transport.ts + ports.ts +
extension.test.ts +71 + story .md); collision guard held (mesh_node.ts/
session/bridge.ts/transport/pi_forward_client.ts untouched — injected-relay
ownership contract preserved). Lifecycle verified: `_attachBridgeIfReady` reduced
to a one-line compat shim into `_relayTransport.attachCrossPcBridge()`; start/
reconnect-success re-attach after the relay is current; unexpected-close/stop
detach before state publication; late-attach re-check captures currentRelay/
currentRelayUrl/currentKeypair before the await and re-checks after (relay still
current). Best-effort preserved (bridge failure doesn't break app pairing or
local UDS mesh). Bridge tests (relay-drop-detaches + reconnect-re-attaches) green.
