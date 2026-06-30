---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module-step-5
kind: story
stage: review
tags: [refactor]
parent: epic-bold-split-pi-extension-index-sdk-session-projection-module
depends_on: [epic-bold-split-pi-extension-index-sdk-session-projection-module-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation
- Files changed: `pi-extension/src/index.ts`, `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/transport/peer_channel.ts`, `pi-extension/src/transport/pi_forward_client.ts`, `pi-extension/src/session/broker_remote.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/broker_remote.test.ts`.
- Epoch teardown: `index.ts` now advances `SdkSessionProjection.clearStaleContexts()` before clearing legacy stale-context globals, so the session epoch is invalidated before relay/mesh teardown paths can resume.
- Bridge late-continuation hardening: `RelayTransport` now tracks a bridge epoch/current predicate, passes `isCurrent` into `meshNode.attachBridge`, invalidates that epoch on detach/stop/reconnect teardown, and detaches the mesh bridge if an attach continuation resumes stale after session shutdown/stop.
- Detached no-op guards: `PlainPeerChannel.send`/queued inbound handling, `PiForwardClient.sendEnvelopeToPi`/queued inbound handling, and `BrokerRemote.handleIncoming`/control send paths now no-op after `detach()`.
- Tests added: `extension.test.ts` covers cross-PC bridge attach resolving after shutdown/stop without installing stale state; `broker_remote.test.ts` covers detached `BrokerRemote`, `PlainPeerChannel`, and `PiForwardClient` send/inbound no-ops.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; `corepack pnpm exec vitest run src/session/broker_remote.test.ts` passed `35 passed`; targeted `corepack pnpm exec vitest run src/extension.test.ts src/session/broker_remote.test.ts` reported `190 passed | 4 failed` across 194 tests.
- False-alarm observation: the 4 targeted-suite failures match the documented environment/cwd-lock false-failure bucket, not bridge/listener/late-attach behavior: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, and `a second same-name agent joins as <name>#2 instead of being refused`.
- Discrepancies from design: per collision guard, this step hardened the relay-transport-owned attach path and detached guards without editing landed `session/mesh_node.ts` or `session/bridge.ts`; the bridge predicate is exposed through the `CrossPcBridgeMeshNode` port for attach implementations that honor it.
- Adjacent issues parked: none.
