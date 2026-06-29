---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-sdk-session-projection-module
depends_on: [epic-bold-split-pi-extension-index-sdk-session-projection-module-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Harden session epoch teardown and cross-PC bridge late continuations

## Current State
```ts
// pi-extension/src/session/bridge.ts
export async function attachCrossPcBridge(opts: AttachBridgeOptions): Promise<CrossPcBridge> {
  const piForward = new PiForwardClient(opts.relay);
  // awaits sibling discovery here
  const brokerRemote = new BrokerRemote({ broker: opts.broker, pi: piForward, ... });
  return { brokerRemote, piForward };
}

// pi-extension/src/session/mesh_node.ts
const { brokerRemote, piForward } = await attachCrossPcBridge({ broker, relay, relayUrl, keypair, log });
this.brokerRemote = brokerRemote;
this.piForward = piForward;
```

A shutdown can land while sibling discovery is awaiting, letting a stale `PiForwardClient`/`BrokerRemote` install after teardown.

## Target State
```ts
// pi-extension/src/session/bridge.ts
export interface AttachBridgeOptions {
  broker: Broker;
  relay: RelayClient;
  relayUrl: string;
  keypair: Ed25519Keypair;
  isCurrent?: () => boolean;
  log?: (msg: string) => void;
}

export async function attachCrossPcBridge(opts: AttachBridgeOptions): Promise<CrossPcBridge | null> {
  const piForward = new PiForwardClient(opts.relay);
  try {
    const siblings = await discoverSiblingSnapshot(opts);
    if (opts.isCurrent && !opts.isCurrent()) { piForward.detach(); return null; }
    const brokerRemote = new BrokerRemote({ broker: opts.broker, pi: piForward, siblings, log: opts.log, ...labels });
    if (opts.isCurrent && !opts.isCurrent()) { brokerRemote.detach(); piForward.detach(); return null; }
    return { brokerRemote, piForward };
  } catch (err) {
    piForward.detach();
    throw err;
  }
}
```

```ts
// pi-extension/src/session/mesh_node.ts
const bridgeEpoch = ++this.bridgeEpoch;
const bridge = await attachCrossPcBridge({
  broker,
  relay,
  relayUrl: params.relayUrl,
  keypair: this.keypair,
  log: this.log,
  isCurrent: () => this.bridgeEpoch === bridgeEpoch && this.bridgeParams === params,
});
if (!bridge) return;
this.brokerRemote = bridge.brokerRemote;
this.piForward = bridge.piForward;
```

## Implementation Notes
- `SdkSessionProjection.clearStaleContexts()` increments the session epoch before any awaited teardown.
- Bridge attach paths receive an epoch/current predicate from their owning transport/session root.
- Add detached guards to `PlainPeerChannel.send`, `PlainPeerChannel._onLine`, `BrokerRemote.handleIncoming`, and `PiForwardClient._handleLine`.
- Do not change relay protocol, peer address format, anti-spoof checks, or cross-PC authorization.

## Acceptance Criteria
- [ ] A `MeshNode.attachBridge()` / `attachCrossPcBridge()` continuation that resumes after `detachBridge()`, `MeshNode.close()`, or `session_shutdown` detaches any partial `PiForwardClient` and does not install `BrokerRemote`.
- [ ] `PlainPeerChannel`, `BrokerRemote`, and `PiForwardClient` ignore sends/inbound events after `detach()`.
- [ ] Existing cross-PC routing tests still pass; new regression tests cover late attach after shutdown and detached inbound event no-op.
- [ ] `corepack pnpm typecheck` and targeted `corepack pnpm test -- extension broker_remote` pass from `pi-extension/`.

## Risk
Medium. This touches cross-PC bridge lifecycle but should be behavior-preserving when the bridge is current.

## Rollback
Remove the epoch/current predicate and detached guards, restoring the previous attach flow. If rollback is necessary, file/keep a follow-up bug because this reopens the ghost-listener race.
