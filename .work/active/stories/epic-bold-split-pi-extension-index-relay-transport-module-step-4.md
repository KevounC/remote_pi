---
id: epic-bold-split-pi-extension-index-relay-transport-module-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-relay-transport-module
depends_on: [epic-bold-split-pi-extension-index-relay-transport-module-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
