---
id: epic-bold-turn-state-machine-late-attach-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-turn-state-machine-late-attach
depends_on: [epic-bold-turn-state-machine-late-attach-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Guard cross-PC bridge late attach with a lifecycle epoch

**Priority**: High  
**Risk**: Medium  
**Source Lens**: lifecycle ownership / code smell  
**Files**: `pi-extension/src/session/mesh_node.ts`, `pi-extension/src/session/bridge.ts`, `pi-extension/src/session/mesh_node.test.ts` or focused existing session test file

## Current State

```ts
private async _maybeBridge(): Promise<void> {
  if (this.brokerRemote) return;
  if (this.peer_.currentRole() !== "leader") return;
  const broker: Broker | null = this.peer_.localBroker();
  if (!broker) return;
  const params = this.bridgeParams;
  if (!params) return;
  // ... relay/key setup ...
  const { brokerRemote, piForward } = await attachCrossPcBridge({
    broker,
    relay,
    relayUrl: params.relayUrl,
    keypair: this.keypair,
    log: this.log,
  });
  this.brokerRemote = brokerRemote;
  this.piForward = piForward;
}
```

`attachCrossPcBridge()` constructs a `PiForwardClient`, awaits sibling discovery, and then returns live bridge objects. If `MeshNode.close()` / `detachBridge()` lands during that await window, the continuation can still retain relay/broker listeners after teardown.

## Target State

```ts
private bridgeEpoch = 0;
private closed = false;

private _nextBridgeEpoch(): number {
  return ++this.bridgeEpoch;
}

private _isBridgeEpochCurrent(epoch: number, params: BridgeParams, broker: Broker, relay: RelayClient): boolean {
  return !this.closed &&
    this.bridgeEpoch === epoch &&
    this.bridgeParams === params &&
    this.peer_.currentRole() === "leader" &&
    this.peer_.localBroker() === broker &&
    this.relay === relay;
}

private async _maybeBridge(): Promise<void> {
  if (this.closed || this.brokerRemote) return;
  if (this.peer_.currentRole() !== "leader") return;
  const broker = this.peer_.localBroker();
  const params = this.bridgeParams;
  if (!broker || !params) return;
  const epoch = this._nextBridgeEpoch();
  // ... relay/key setup with post-await epoch checks ...
  const bridge = await attachCrossPcBridge({ broker, relay, relayUrl: params.relayUrl, keypair: this.keypair, log: this.log });
  if (!this._isBridgeEpochCurrent(epoch, params, broker, relay)) {
    bridge.brokerRemote.detach();
    bridge.piForward.detach();
    return;
  }
  this.brokerRemote = bridge.brokerRemote;
  this.piForward = bridge.piForward;
}

async close(): Promise<void> {
  this.closed = true;
  this.detachBridge();
  await this.peer_.leave();
}
```

Optional bridge-level signal if cleaner:

```ts
export interface AttachBridgeOptions {
  // existing fields...
  isCurrent?: () => boolean;
}
```

`attachCrossPcBridge()` may use `isCurrent` after sibling discovery and before constructing `BrokerRemote`, but `MeshNode` must still detach any returned bridge if it becomes stale between the final guard and assignment.

## Implementation Notes

- Treat this as the same late-attach class as owner late attach: an async continuation can attach after its owner has moved to a terminal state. The owner here is `MeshNode` rather than a mobile channel.
- Increment the epoch on `detachBridge()`, `_detachBridgeKeepingParams()`, UDS failover reattach, relay self-reconnect, and `close()` so stale continuations cannot win after teardown or replacement.
- Do not close an injected relay from this guard; injected relay lifecycle remains owned by `index.ts`.
- If a stale `attachCrossPcBridge()` already constructed `PiForwardClient` / `BrokerRemote`, immediately detach both before returning.
- Keep logs payload-free and best-effort.

## Acceptance Criteria

- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] A deterministic regression test parks sibling discovery or bridge construction, calls `MeshNode.close()` / `detachBridge()`, releases discovery, and asserts `hasBridge()` remains false.
- [ ] The same regression asserts no relay envelope listeners or broker remote listeners remain after the stale continuation resolves.
- [ ] Existing cross-PC bridge/e2e tests still pass.
- [ ] Injected-relay callers still do not have their relay closed by `MeshNode`.

## Risk

Medium. The main risk is over-invalidating a legitimate failover/reconnect bridge and leaving cross-PC routing down until the next reconnect.

## Rollback

Revert `mesh_node.ts`, `bridge.ts`, and the focused bridge late-attach test. This does not require reverting the turn reducer or owner late-attach integration.
