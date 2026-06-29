---
id: epic-bold-split-pi-extension-index-relay-transport-module
kind: feature
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Split pi-extension index — relay transport module

## Brief
Relay transport lifecycle (reconnect, liveness, control frames) extracted from
`index.ts` as a named module. Adopts the `epic-bold-reachability-contract`
state machine. Globals `_relay`, `_lastRelayStatus`, `_relayUrl`,
`_reconnectTimer`, `_reconnectAttempt` (`index.ts:128-147`, `:587-588`) become
this module's private state.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:128-147`, `:587-588`;
  `pi-extension/src/transport/relay_client.ts`.

<!-- /agile-workflow:refactor-design pins the module boundary. -->

## Design decisions
- Autopilot judgment mode: treat this as a pure structure-preserving refactor. Public relay wire frames, app protocol, CLI command names/output, reconnect timing, auth sequence, room metadata semantics, ping/liveness behavior, and cross-PC envelope format must stay unchanged.
- Dispatch rationale: direct-read design only. This delegated sub-agent does not have a sub-agent dispatch tool available in its active tool namespace, so no exploratory fan-out was possible despite the raised implementation tier. The target is bounded (`index.ts` relay lifecycle plus `transport/` and `session/bridge` relay consumers), and the plan is grounded in direct reads of the feature/epic, composition-root design, reachability pi-adapter design, foundation docs, `PROTOCOL.md`, stack references, `index.ts`, `relay_client.ts`, `peer_channel.ts`, `pi_forward_client.ts`, `mesh_node.ts`, `bridge.ts`, and relevant tests.
- Module boundary: the new adapter lives at the extension-runtime boundary (suggested `pi-extension/src/extension/relay_transport.ts`) and implements the composition-root `RelayTransportPort`. `transport/relay_client.ts` remains the low-level WebSocket/auth/liveness client; the new module owns lifecycle orchestration around that client.
- Reachability coordination: `epic-bold-reachability-contract-pi-adapter` owns the shared timing projection. This module consumes that projection rather than creating a second backoff/liveness registry. Step 1 therefore depends on `epic-bold-reachability-contract-pi-adapter-step-4` as well as the composition-root feature.
- Patchbay migration guard: name the port by generic host responsibility (`RelayTransportPort`) and inject clock/timer/URL/client dependencies. Do not bake Remote-Pi-only global names or Pi SDK contexts into the transport module; future patchbay hosts should be able to provide an equivalent adapter.
- SelfRevoke/pairing boundary: `SelfRevoke` is relay-up lifecycle-adjacent but owns mesh membership and pairing side effects, so it stays outside the transport module in this refactor. The relay module may expose connection lifecycle callbacks used by the membership/owner modules, but it should not own `peers.json`, owner revocation, or mobile pairing persistence.
- Cycle check: `.work/bin/work-view --blocking` is unavailable in this checkout (`.work/bin/` is empty), so the dependency graph was checked by frontmatter. New story chain is linear. Step 1 depends on `epic-bold-split-pi-extension-index-composition-root` and `epic-bold-reachability-contract-pi-adapter-step-4`; no reverse dependency from those items to this feature/story exists. Steps 2-5 depend only on the preceding step.

## Refactor Overview
`pi-extension/src/index.ts` currently owns relay transport as shared mutable globals while also owning owner channels, SDK session projection, command dispatch, pairing, daemon setup, and mesh state. The low-level `RelayClient` already isolates WebSocket auth and liveness, but the runtime lifecycle around it—start, reconnect, stop, relay-state emission, room-meta control frames, and cross-PC bridge attachment—is still smeared across the god file.

This feature extracts that lifecycle into a named `RelayTransportPort` adapter. The adapter owns the live `RelayClient`, canonical relay URL, current room id/meta snapshot, reconnect timer/attempt counter, relay-state dedupe, control-frame sending, and cross-PC bridge attach/detach hooks. `index.ts` and the future owner/session/command modules interact with relay transport through the port, while `RelayClient`, `PlainPeerChannel`, `PiForwardClient`, `MeshNode`, and `BrokerRemote` preserve their existing wire behavior.

## Refactor Steps

### Step 1: Introduce the RelayTransportPort adapter module shell
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / lifecycle ownership
**Files**: `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/reachability/reachability_contract.ts`
**Story**: `epic-bold-split-pi-extension-index-relay-transport-module-step-1`

**Current State**:
```ts
// pi-extension/src/index.ts
let _relay: RelayClient | null = null;
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";
let _lastRelayStatus: RelayConnectivity | null = null;
let _relayUrl: string | null = null;
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
let _reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let _reconnectAttempt = 0;
```

**Target State**:
```ts
// pi-extension/src/extension/relay_transport.ts
export interface RelayTransportDeps {
  createRelay(url: string, keypair: Ed25519Keypair): RelayClient;
  toWebSocketUrl(url: string): string;
  backoffMs(attempt: number): number;
  setTimer(cb: () => void, delayMs: number): ReturnType<typeof setTimeout>;
  clearTimer(timer: ReturnType<typeof setTimeout>): void;
}

export function createRelayTransportPort(deps: RelayTransportDeps): RelayTransportPort {
  let relay: RelayClient | null = null;
  let relayUrl: string | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let reconnectAttempt = 0;
  let lastStatus: RelayConnectivity | null = null;
  // start/stop/status/sendRoomMeta/onOuterMessage/attachCrossPcBridge live here.
}
```

**Implementation Notes**:
- Keep `RelayClient` as the low-level WebSocket/auth/liveness adapter; do not inline it into the runtime module.
- Import backoff/liveness policy from `reachability/reachability_contract.ts`; do not introduce a new timing registry.
- If composition-root implementation has not yet named the exact port file, adapt to its chosen `RelayTransportPort` export rather than creating a parallel interface.
- A temporary internal relay handle escape hatch is acceptable only to keep owner-channel wiring compatible until Step 5; document it as temporary.

**Acceptance Criteria**:
- [ ] Adapter module exists and implements the composition-root `RelayTransportPort`.
- [ ] Private relay/reconnect/status state is introduced in the module, not as new `index.ts` globals.
- [ ] Reachability projection provides the timer policy.
- [ ] No runtime behavior changes in this shell step.
- [ ] `corepack pnpm typecheck` passes.

**Rollback**: Delete the new adapter module and remove its type-only imports.

---

### Step 2: Move relay start, close, reconnect, and relay-state emission into the module
**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle ownership
**Files**: `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-relay-transport-module-step-2`

**Current State**:
```ts
// pi-extension/src/index.ts
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

**Target State**:
```ts
const result = await ports.relay.start({
  relayUrl,
  keypair: edKp,
  roomId,
  roomMeta,
  shouldStayCurrent: () => !_disposed && _state !== "idle",
  onUnexpectedClose: () => {
    legacyOwners.detachAllForRelayDrop();
    legacyMesh.detachCrossPcBridge();
    _state = "started";
    _refreshFooter();
  },
  emitRelayState: (snapshot) => _emitRelayStateFromTransport(snapshot),
});
```

**Implementation Notes**:
- Preserve `RoomAlreadyOpenError` handling and notification text.
- Preserve post-connect `_disposed` guard by closing a relay that succeeds after session shutdown before it becomes current.
- Preserve reconnect room replay: same `roomId` and latest `roomMeta` must be passed to every reconnect `hello`.
- Preserve `/remote-pi stop` timer cancellation.
- Keep SelfRevoke creation in command/mesh membership code; call it from a connection-success callback if needed.

**Acceptance Criteria**:
- [ ] `index.ts` no longer owns `_relay`, `_relayUrl`, `_reconnectTimer`, `_reconnectAttempt`, or `_lastRelayStatus` directly.
- [ ] Reconnect tests still prove `1s,2s,5s,10s,30s...`, stop cancellation, successful-counter reset, and room-meta replay.
- [ ] `remote-pi:relay-state` events keep their exact current detail shape.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "relay reconnect|relay control channel|reconnect replays"` passes.
- [ ] `corepack pnpm typecheck` passes.

**Rollback**: Restore the previous relay globals and start/close/reconnect functions in `index.ts`; leave the shell module unused or delete it.

---

### Step 3: Centralize relay control frames and room-meta updates behind RelayTransportPort
**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / single source of truth
**Files**: `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-relay-transport-module-step-3`

**Current State**:
```ts
function _publishWorking(working: boolean): void {
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, working };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { working } });
  }
}
```

Direct `sendControl` calls also publish `model`, `thinking`, and `session_id`.

**Target State**:
```ts
function _publishWorking(working: boolean): void {
  _myRoomMeta = _myRoomMeta ? { ..._myRoomMeta, working } : _myRoomMeta;
  ports.relay.sendRoomMeta({ working });
}

ports.relay.sendRoomMeta({ model: modelName });
ports.relay.sendRoomMeta({ thinking: level });
ports.relay.sendRoomMeta({ session_id: sessionId });
```

```ts
sendRoomMeta(patch: Partial<RoomMeta>): void {
  roomMeta = roomMeta ? { ...roomMeta, ...patch } : roomMeta;
  if (!relay || !roomId) return;
  relay.sendControl({ type: "room_meta_update", room_id: roomId, meta: patch });
}
```

**Implementation Notes**:
- Best-effort/no-throw control-frame behavior stays in the transport module.
- Cached room meta must update even when the relay is down so reconnect hello is authoritative.
- No new fields, casing changes, debouncing, or protocol validation changes.

**Acceptance Criteria**:
- [ ] `room_meta_update` sends route through one relay transport method.
- [ ] Model/thinking/session/working reconnect snapshots stay current.
- [ ] Existing model meta, turn working, compaction, and reconnect-after-model-select tests pass.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "model meta|working|compaction|reconnect after model_select"` passes.
- [ ] `corepack pnpm typecheck` passes.

**Rollback**: Restore direct `_relay.sendControl(...)` call sites in `index.ts`.

---

### Step 4: Move cross-PC relay bridge attach/detach ownership behind RelayTransportPort
**Priority**: Medium
**Risk**: Medium
**Source Lens**: lifecycle ownership / ports and adapters
**Files**: `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/index.ts`, `pi-extension/src/session/mesh_node.ts`, `pi-extension/src/session/bridge.ts`
**Story**: `epic-bold-split-pi-extension-index-relay-transport-module-step-4`

**Current State**:
```ts
function _attachBridgeIfReady(): void {
  if (!_meshNode || !_relay || !_relayUrl || !_cachedEd25519) return;
  void _meshNode
    .attachBridge({ relay: _relay, relayUrl: _relayUrl, keypair: _cachedEd25519 })
    .catch(() => { /* best-effort — UDS mesh works regardless */ });
}
```

`_goIdle` and `_onRelayClose` call `_meshNode?.detachBridge()` directly.

**Target State**:
```ts
ports.relay.attachCrossPcBridge({
  meshNode: () => _meshNode,
  keypair: () => _cachedEd25519,
});
```

```ts
async function attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void> {
  const meshNode = input.meshNode();
  const keypair = input.keypair();
  if (!meshNode || !relay || !relayUrl || !keypair) return;
  await meshNode.attachBridge({ relay, relayUrl, keypair }).catch(() => undefined);
}

function detachCrossPcBridge(): void {
  bridgeInput?.meshNode()?.detachBridge();
}
```

**Implementation Notes**:
- `MeshNode`, `BrokerRemote`, and `PiForwardClient` retain their current responsibilities and injected-relay ownership rule.
- Relay start and successful reconnect attach the bridge after the relay becomes current; stop and unexpected close detach it.
- Re-check current relay/epoch after awaits before keeping any bridge state.

**Acceptance Criteria**:
- [ ] `_attachBridgeIfReady` is removed or reduced to a relay-port compatibility call.
- [ ] Relay start/reconnect/local mesh join/close/stop attach and detach cross-PC bridge at the same observable points.
- [ ] Existing cross-PC bridge tests pass, and an extension test proves reconnect re-attaches when a mesh leader exists.
- [ ] `corepack pnpm test -- src/extension.test.ts src/session/broker_remote.test.ts` passes.
- [ ] `corepack pnpm typecheck` passes.

**Rollback**: Restore direct `_attachBridgeIfReady()` and `_meshNode?.detachBridge()` calls in `index.ts`.

---

### Step 5: Route owner ingress through RelayTransportPort and lock compatibility tests
**Priority**: High
**Risk**: High
**Source Lens**: missing abstraction / pattern drift
**Files**: `pi-extension/src/extension/relay_transport.ts`, `pi-extension/src/index.ts`, `pi-extension/src/transport/peer_channel.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/transport/relay_client.test.ts`
**Story**: `epic-bold-split-pi-extension-index-relay-transport-module-step-5`

**Current State**:
```ts
_stopAutoListener = _installAutoListener(relay);

function _installAutoListener(relay: RelayClient): () => void {
  const onMsg = async (line: string) => { /* pair_request / known-peer attach */ };
  relay.on("message", onMsg);
  return () => relay.off("message", onMsg);
}

const channel = new PlainPeerChannel(
  relay,
  appPeerId,
  _myRoomId ?? undefined,
  (msg) => _routeClientMessageFrom(channel, msg, _lastEventCtx ?? _lastCtx ?? _noopCtx),
  () => _onPeerDisconnect(appPeerId),
);
```

**Target State**:
```ts
const unsubscribe = ports.relay.onOuterMessage((line) => {
  void legacyOwnerIngress.handleOuterLine(line);
});

const channel = ports.relay.createPeerChannel({
  peerId: appPeerId,
  roomId: currentRoomId,
  onMessage: (msg) => owners.routeFrom(channel, msg),
  onDisconnect: () => owners.detach(appPeerId),
});
```

If the implemented composition-root port does not include `createPeerChannel`, keep exactly one documented temporary legacy relay-handle accessor for the owner-multiplexer feature to remove.

**Implementation Notes**:
- Preserve known-peer reconnect single-delivery behavior: the consumed line is routed exactly once after attaching.
- Preserve unknown-peer error and avoid logging payloads.
- Preserve `PlainPeerChannel` wire shape and test-only compatibility shims.
- Avoid duplicate relay listeners during reconnect; owner channels must detach on relay close and reattach via known-peer flow.

**Acceptance Criteria**:
- [ ] Owner ingress uses `RelayTransportPort.onOuterMessage()` or one named temporary legacy adapter, not scattered `relay.on("message")` calls in `index.ts`.
- [ ] Pairing, known-peer reconnect, unknown-peer error, multi-owner fanout, session_sync, relay liveness, and reconnect tests pass.
- [ ] `RelayClient`, `PlainPeerChannel`, and `PiForwardClient` public behavior is unchanged.
- [ ] `corepack pnpm test -- src/extension.test.ts src/transport/relay_client.test.ts` passes.
- [ ] `corepack pnpm typecheck` passes.

**Rollback**: Restore direct `_installAutoListener(relay)` and `new PlainPeerChannel(relay, ...)` construction in `index.ts`.

## Implementation Order
1. `epic-bold-split-pi-extension-index-relay-transport-module-step-1` — create the RelayTransportPort adapter shell after the composition-root feature and reachability pi-adapter liveness step land.
2. `epic-bold-split-pi-extension-index-relay-transport-module-step-2` — move start/close/reconnect/status ownership into the adapter.
3. `epic-bold-split-pi-extension-index-relay-transport-module-step-3` — centralize room-meta control frames through the adapter.
4. `epic-bold-split-pi-extension-index-relay-transport-module-step-4` — move cross-PC bridge attach/detach lifecycle behind the adapter.
5. `epic-bold-split-pi-extension-index-relay-transport-module-step-5` — route owner ingress through the adapter and lock compatibility tests.

## Convention-driven steps
No project-specific `.agents/skills/refactor-conventions/` catalog exists. The design uses the default refactor-design lenses plus repo rules: ports/adapters, single source of truth, fail-fast boundaries, lifecycle ownership, convergent state, and test integrity.

## Atomic steps acknowledged
No step intentionally changes public protocol, relay wire format, CLI API, or user-visible behavior. Step 2 is the semi-atomic lifecycle transfer because live relay ownership, reconnect scheduling, and relay-state emission must agree in one commit. Step 5 is the semi-atomic ingress transfer because duplicate or missing relay listeners can double-deliver or drop app messages. Both remain rollbackable by restoring the previous `index.ts` wiring.
