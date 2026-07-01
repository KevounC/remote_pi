---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module
kind: feature
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: extension-0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Split pi-extension index — owner multiplexer module

## Brief
`_activePeers` fanout (`_broadcastToActive`, `index.ts:620-635`) + pairing as a
named module. Globals `_activePeers`, `_peerShort`, `_meshNode`, `_sessionName`,
`_sessionPeerCount`, `_hasGlobalPairings` (`index.ts:160-195`) become this
module's private state.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:160-195`, `:620-635`, `:1157-1167`,
  `:1238-1244`.

<!-- /agile-workflow:refactor-design pins the module boundary. -->

## Design decisions
- Autopilot judgment mode: resolve ambiguities locally and preserve behavior. This is a fork-private bold refactor, but the black-box contract stays stable: same relay frames, same app protocol, same CLI/status wording unless a later implementation story explicitly proves a structural alias is equivalent.
- Dispatch rationale: direct-read design only. The delegated sub-agent tool namespace did not expose a child-agent dispatcher, so no exploratory fan-out was possible despite the raised implementation tier. The target is bounded and grounded in direct reads of foundation docs, `PROTOCOL.md`, the composition-root design, canonical-session identity design, `index.ts`, `transport/peer_channel.ts`, `pairing/storage.ts`, `session/peer*.ts`, and multi-owner tests.
- Port boundary: implement the composition-root `OwnerMultiplexerPort`; do not create a second owner API. The module owns owner channels, active-owner fanout, pair/known/unknown owner ingress, sender-specific replies, late-attach owner targets, and owner-visible pairing/peer projection state.
- Mesh-node judgment: the brief names `_meshNode`, `_sessionName`, and `_sessionPeerCount`. After reading the composition-root design, keep `MeshNode` socket/bridge lifecycle with the command/mesh surface, but move the owner-visible projection (`sessionName`, `sessionPeerCount`) into the owner multiplexer snapshot. That removes display/status globals without making owner-channel code own broker sockets.
- Session-id posture: carry `session_id` opaquely. Owner multiplexing remains keyed by owner peer id plus the current extension room; session discrimination belongs to the canonical-session/session-projection work, not relay or owner-channel selection.
- Pairing semantics: `peers.json` remains machine-global and accepts N Owner records. Pairing another Owner must not disconnect existing Owners. Re-pairing the same Owner remains idempotent by `remote_epk`.
- Patchbay migration guard: name dependencies by generic owner-channel/pairing responsibilities and inject channel creation, storage, token, and notification functions. Do not bake fork-specific global names into the extracted module.
- Cycle check: `.work/bin/work-view --blocking` is unavailable in this checkout (`.work/bin/` is empty; command exited 127). Manual frontmatter check found no existing owner-multiplexer step stories and no reverse dependency to this feature. The emitted chain is linear: step 1 depends on `epic-bold-split-pi-extension-index-composition-root`, steps 2-5 depend on the immediately preceding owner-multiplexer step.

## Refactor Overview
`pi-extension/src/index.ts` currently owns app Owner channels through `_activePeers`, sender-specific `PlainPeerChannel` callbacks, pair/known/unknown owner ingress, global pairing cache, footer peer hints, and revocation/disconnect behavior while also owning relay lifecycle and SDK session projection. The current behavior is correct enough to preserve: one active channel per Owner peer id in the current extension room, multiple Owners may attach to the same PC, broadcast session events fan out to every attached Owner, sender-specific requests (`session_sync`, `ping`, `cancel`) reply only to the sender, and relay-level broadcast/fanout remains outside the extension module.

This refactor extracts those concerns into a named owner multiplexer module implementing `OwnerMultiplexerPort`. `index.ts` and sibling modules stop mutating the owner map directly; they call the port for attach/detach/broadcast/route/snapshot operations. Pairing storage remains in `pairing/storage.ts`; low-level relay channel encoding remains in `transport/peer_channel.ts`; canonical session validation stays opaque to this module.

## Refactor Steps

### Step 1: Introduce the OwnerMultiplexerPort adapter shell
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / lifecycle ownership
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/index.ts`
**Story**: `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-1`

**Current State**:
```ts
// pi-extension/src/index.ts
const _activePeers = new Map<string, PlainPeerChannel>();
let _peerShort = "";
let _hasGlobalPairings = false;

function _broadcastToActive(msg: ServerMessage): void { /* map fanout */ }
function _attachOwner(relay: RelayClient, appPeerId: string, peerName: string): PlainPeerChannel { /* constructs PlainPeerChannel */ }
function _installAutoListener(relay: RelayClient): () => void { /* pair/known/unknown ingress */ }
```

**Target State**:
```ts
// pi-extension/src/extension/owner_multiplexer.ts
export interface OwnerMultiplexerDeps {
  createChannel(input: CreateOwnerChannelInput): PeerChannelHandle;
  findKnownPeer(appPeerId: string): Promise<PeerRecord | null>;
  addPeer(record: PeerRecord): Promise<void>;
  listPeers(): Promise<PeerRecord[]>;
  consumePairToken(token: string): PairTokenStatus;
  makePairOk(input: PairOkInput): ServerMessage;
  notify(message: string, type?: "info" | "warning" | "error"): void;
  refreshFooter(): void;
  routeClientMessage(sender: PeerChannel, message: ClientMessage): void;
}

export function createOwnerMultiplexerPort(deps: OwnerMultiplexerDeps): OwnerMultiplexerPort {
  const channels = new Map<string, PeerChannelHandle>();
  let peerShort = "";
  let hasGlobalPairings = false;
  // activeCount/attach/detach/broadcast/routeFrom/lateAttachTargets implemented here.
}
```

**Implementation Notes**:
- Use the `OwnerMultiplexerPort` exported by the composition-root work; do not create a parallel interface.
- Keep the shell mostly type-first: dependency injection, private map state, and method skeletons that can wrap legacy helpers before bodies move.
- Model channel identity as the current runtime invariant: one live channel per `(owner peer id, current relay room)` at the extension. Because a started extension runtime owns one room at a time, the internal map key can remain `appPeerId`.
- Patchbay guard: dependencies are generic owner-channel and pairing primitives, not Pi-SDK globals or fork-specific god-file names.

**Acceptance Criteria**:
- [ ] `owner_multiplexer.ts` exists and compiles as an ESM/NodeNext module.
- [ ] It implements the composition-root `OwnerMultiplexerPort` shape without changing public protocol, CLI output, or relay frames.
- [ ] `_activePeers`, `_peerShort`, and `_hasGlobalPairings` have a named target owner in the new module, even if legacy wrappers still feed them during this step.
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.

**Rollback**: Delete `owner_multiplexer.ts` and remove any type-only imports or legacy adapter references added in this step.

---

### Step 2: Move owner channel registry and fanout into the module
**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/index.ts`, `pi-extension/src/transport/peer_channel.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-2`

**Current State**:
```ts
function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
  if (_turnActive) _peersAttachedDuringTurn.add(appPeerId);
}

function _detachPeerChannel(appPeerId: string): void {
  const ch = _activePeers.get(appPeerId);
  if (!ch) return;
  try { ch.detach(); } catch { /* best-effort */ }
  _activePeers.delete(appPeerId);
  const next = _activePeers.keys().next().value;
  _peerShort = next ? next.slice(0, 8) : "";
}

function _broadcastToActive(msg: ServerMessage): void {
  for (const ch of _activePeers.values()) {
    try { ch.send(msg); } catch { /* best-effort per channel */ }
  }
}
```

**Target State**:
```ts
class OwnerMultiplexer implements OwnerMultiplexerPort {
  private readonly channels = new Map<string, PeerChannelHandle>();
  private peerShort = "";
  private lateAttachPeerIds = new Set<string>();

  activeCount(): number { return this.channels.size; }
  peerHint(): string { return this.peerShort; }

  attach(input: AttachOwnerInput): PeerChannel {
    this.detach(input.peerId);
    const channel = this.deps.createChannel({
      peerId: input.peerId,
      roomId: input.roomId,
      onMessage: (message) => this.routeFrom(channel, message),
      onDisconnect: () => this.detach(input.peerId, "disconnect"),
    });
    this.channels.set(input.peerId, channel);
    this.peerShort = input.peerId.slice(0, 8);
    if (input.turnActive) this.lateAttachPeerIds.add(input.peerId);
    return channel;
  }

  detach(peerId: string): void { /* detach one, preserve others */ }
  detachAll(reason?: ByeReason): void { /* optional bye then detach every channel */ }
  broadcast(message: ServerMessage): void { /* best-effort fanout to every channel */ }
  lateAttachTargets(): PeerChannel[] { /* consume marked channels */ }
}
```

**Implementation Notes**:
- Preserve idempotent reattach: attaching the same owner peer id first detaches the stale channel to avoid duplicate relay listeners.
- Preserve best-effort fanout: one owner's `send()` failure must not prevent delivery to other owners.
- Preserve derived `paired` state: callers derive it from `activeCount() > 0`, not from a third `_state` enum value.
- Keep `PlainPeerChannel` as the low-level relay-backed channel; the owner module owns channel lifetime, not websocket auth or liveness.
- Keep relay broadcast semantics unchanged: the extension sends one per-owner outbound envelope through each live channel; the relay remains responsible for lower-level connection fanout and skip-sender behavior.

**Acceptance Criteria**:
- [ ] `_activePeers` map mutation is replaced by OwnerMultiplexer methods.
- [ ] `broadcast()` still sends to every attached owner and isolates per-channel exceptions.
- [ ] Detaching one owner leaves other owners connected and leaves relay started.
- [ ] Late-attach tracking still records owners attached during an active turn for catch-up history.
- [ ] Existing multi-channel tests for two owners, `agent_chunk` broadcast, revoke-one-owner, and queued-message fanout pass.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "multi-channel broadcast"` and `corepack pnpm typecheck` pass.

**Rollback**: Restore `_activePeers`, `_peerShort`, `_attachPeerChannel`, `_detachPeerChannel`, `_broadcastToActive`, and `_anyPeerActive` in `index.ts`.

---

### Step 3: Move owner ingress, pairing, and reconnect attach decisions
**Priority**: High
**Risk**: High
**Source Lens**: code smell / fail-fast boundary
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/index.ts`, `pi-extension/src/pairing/storage.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-3`

**Current State**:
```ts
function _installAutoListener(relay: RelayClient): () => void {
  const onMsg = async (line: string) => {
    const outer = JSON.parse(line) as { peer?: string; ct?: string };
    if (_activePeers.has(outer.peer)) return;
    const inner = JSON.parse(Buffer.from(outer.ct, "base64").toString("utf8")) as ClientMessage;
    if (inner.type === "pair_request") await _handlePairRequest(relay, appPeerId, inner);
    const known = await _findKnownPeer(appPeerId);
    if (known) {
      const channel = _attachOwner(relay, appPeerId, known.name);
      _routeClientMessageFrom(channel, inner, _lastEventCtx ?? _lastCtx ?? _noopCtx);
    }
  };
  relay.on("message", onMsg);
  return () => relay.off("message", onMsg);
}
```

**Target State**:
```ts
async handleOuterLine(input: OwnerOuterLineInput): Promise<void> {
  const outer = decodeOuterEnvelope(input.line);
  if (!outer) return;
  if (this.channels.has(outer.peer)) return;

  const inner = decodeClientMessage(outer.ct);
  if (!inner) return;

  if (inner.type === "pair_request") {
    await this.handlePairRequest(input.relay, outer.peer, inner);
    return;
  }

  const known = await this.deps.findKnownPeer(outer.peer);
  if (!input.isCurrent()) return;
  if (known) {
    const channel = this.attach({ peerId: outer.peer, peerName: known.name, roomId: input.roomId, turnActive: input.turnActive() });
    this.routeFrom(channel, inner);
    return;
  }

  input.sendToPeer(outer.peer, { type: "error", code: "unknown_peer", message: "Peer not paired — re-scan QR" });
}
```

**Implementation Notes**:
- Keep `peers.json` semantics unchanged: multiple Owner records are allowed, `addPeer()` remains idempotent by `remote_epk`, and list/remove behavior remains in `pairing/storage.ts`.
- Preserve pair-request token behavior exactly: expired/consumed/unknown map to the same `pair_error` codes/messages; successful pairing sends one sender-specific `pair_ok` and attaches the owner.
- Preserve reconnect behavior: a known owner that sends any non-pair message while no channel is active gets attached and the first consumed inner is routed exactly once.
- Preserve unknown-peer behavior: pair requests from unknown peers are legitimate; non-pair messages from unknown peers get a sender-only `error{unknown_peer}` without logging payload contents.
- Use `unknown` + narrow helpers for outer/inner decode inside the owner boundary. Do not broaden runtime acceptance or change protocol validation semantics.
- Keep `session_id` opaque: pair_ok/session routing may carry it, but the owner multiplexer compares owner peer ids and room identity only.

**Acceptance Criteria**:
- [ ] Auto-listener pairing/reconnect/unknown-peer decisions live behind the owner multiplexer.
- [ ] Pairing a second Owner while one Owner is already attached succeeds and does not disconnect the first.
- [ ] Re-pairing the same Owner remains idempotent and avoids leaked channel listeners.
- [ ] Pair request responses remain sender-specific and use the same wire shape, including opaque `session_id` when present.
- [ ] Existing pair_request, unknown_peer, reconnect race, and multi-owner pairing tests pass.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "pair_request|unknown peer|multi-channel broadcast|shutdown"` and `corepack pnpm typecheck` pass.

**Rollback**: Move `_installAutoListener`, `_findKnownPeer`, and `_handlePairRequest` bodies back into `index.ts` and have the relay transport install the legacy listener directly.

---

### Step 4: Move owner lifecycle projections, revocation hooks, and mesh peer display state
**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / lifecycle ownership
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/index.ts`, `pi-extension/src/session/mesh_node.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-4`

**Current State**:
```ts
let _meshNode: MeshNode | null = null;
let _sessionName: string | null = null;
let _sessionPeerCount = 0;
let _hasGlobalPairings = false;

function _refreshPairingsCache(): void { /* listPeers -> _hasGlobalPairings -> footer */ }
function _refreshSessionPeerCount(peer: MeshNode, ctx?: Pick<ExtensionContext, "ui"> | null): void { /* broker list_peers -> _sessionPeerCount */ }
function _onPeerDisconnect(appPeerId?: string): void { /* detach one owner, preserve relay */ }
// revoke/self-revoke command paths reach into _activePeers directly.
```

**Target State**:
```ts
export interface OwnerMultiplexerSnapshot {
  activeOwnerCount: number;
  ownerShortIds: string[];
  lastOwnerShortId: string;
  hasGlobalPairings: boolean;
  sessionName: string | null;
  sessionPeerCount: number;
}

class OwnerMultiplexer implements OwnerMultiplexerPort {
  private hasGlobalPairings = false;
  private sessionName: string | null = null;
  private sessionPeerCount = 0;

  async refreshPairingsCache(): Promise<void> { /* listPeers -> private cache */ }
  setMeshSession(name: string | null): void { this.sessionName = name; }
  setSessionPeerCount(count: number): void { this.sessionPeerCount = count; }
  snapshot(): OwnerMultiplexerSnapshot { /* footer/status input */ }
  disconnectOwner(peerId?: string): OwnerDisconnectResult { /* legacy _onPeerDisconnect semantics */ }
  revokeOwner(peerId: string): void { /* bye + detach only that owner */ }
  detachAllForRelayDrop(): void { /* relay lost, clear owner channels but keep session projection */ }
}
```

**Implementation Notes**:
- The feature brief names `_meshNode`, `_sessionName`, and `_sessionPeerCount`; after reading the composition-root design, keep `MeshNode` socket/bridge lifecycle with the command/mesh surface, but move the owner-visible peer/session projection (`sessionName`, `sessionPeerCount`) into the owner multiplexer snapshot.
- `_hasGlobalPairings` belongs in this module because it summarizes machine-global paired Owners for footer/status; storage remains in `pairing/storage.ts`.
- Revoking one Owner must send `bye` only to that Owner and must not stop relay, mesh, or other Owner channels.
- Relay drop and full idle teardown use different module methods: relay drop detaches all owner channels without a `bye`; explicit stop/session shutdown may broadcast `bye` before detach when the current behavior does.
- Keep `_refreshFooter` as a consumer of `snapshot()` until a later UI/footer extraction; do not move footer rendering in this feature.

**Acceptance Criteria**:
- [ ] Footer/status callers consume an owner multiplexer snapshot instead of reading `_activePeers`, `_peerShort`, `_sessionName`, `_sessionPeerCount`, or `_hasGlobalPairings` globals.
- [ ] Revoking one Owner sends that Owner `bye` and leaves other Owners attached.
- [ ] Relay close detaches owner channels and clears active owner state while preserving session history and reconnect state owned by sibling modules.
- [ ] Mesh peer count refresh still happens after join and reconnect/failover, but its display value is stored in the owner projection rather than a free global.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "revoke|relay reconnect|footer|peers"` and `corepack pnpm typecheck` pass.

**Rollback**: Restore `_sessionName`, `_sessionPeerCount`, `_hasGlobalPairings`, and owner revocation/detach branches in `index.ts`; leave the channel registry extraction from earlier steps intact if it remains passing.

---

### Step 5: Lock compatibility exports and owner-multiplexer tests
**Priority**: Medium
**Risk**: Medium
**Source Lens**: pattern drift / dead weight prevention
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/extension/testing.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-5`

**Current State**:
```ts
export function _getActivePeerCountForTest(): number { return _activePeers.size; }
export function _hasActivePeerForTest(appPeerIdStd: string): boolean { return _activePeers.has(appPeerIdStd); }
export function _onPeerDisconnect(appPeerId?: string): void { /* direct globals */ }
export function routeClientMessage(msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void {
  const fallback = [..._activePeers.values()].pop();
  if (!fallback) return;
  _routeClientMessageFrom(fallback, msg, ctx);
}
```

**Target State**:
```ts
// pi-extension/src/extension/testing.ts
export interface OwnerMultiplexerTestHarness {
  activeOwnerCount(): number;
  hasOwner(peerId: string): boolean;
  disconnectOwner(peerId?: string): void;
  fallbackRoute(message: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void;
}

// pi-extension/src/index.ts
export const _getActivePeerCountForTest = () => ownerHarness.activeOwnerCount();
export const _hasActivePeerForTest = (peerId: string) => ownerHarness.hasOwner(peerId);
export const _onPeerDisconnect = (peerId?: string) => ownerHarness.disconnectOwner(peerId);
export const routeClientMessage = (msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">) =>
  ownerHarness.fallbackRoute(msg, ctx);
```

**Implementation Notes**:
- Keep existing test exports as aliases so current tests and any out-of-tree operator scripts do not break during the split.
- Add focused unit tests for `OwnerMultiplexer` with fake channel handles: attach same owner replaces the channel, broadcast fans out to all owners, detach one preserves the other, and malformed/unknown ingress is ignored or sender-only errored according to current behavior.
- Keep integration tests for app-visible behavior in `extension.test.ts`; do not replace them with purely structural tests.
- Do not delete legacy comments/history by mass churn. Move only comments that defend the current owner-multiplexer invariant.

**Acceptance Criteria**:
- [ ] Existing `_getActivePeerCountForTest`, `_hasActivePeerForTest`, `_onPeerDisconnect`, and `routeClientMessage` imports still work.
- [ ] New owner-multiplexer unit tests cover attach/detach/broadcast/reconnect-ingress without booting the full extension.
- [ ] Integration tests still cover public behavior: N owners, sender-specific `session_sync`, all-owner rebroadcast, revoke-one-owner, relay drop cleanup.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass.

**Rollback**: Restore test exports to direct `index.ts` globals and remove the owner harness aliases.

## Implementation Order
1. `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-1` — introduce the adapter shell; depends on `epic-bold-split-pi-extension-index-composition-root`.
2. `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-2` — move owner channel registry and broadcast fanout.
3. `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-3` — move pair/known/unknown owner ingress.
4. `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-4` — move owner lifecycle projections, revocation hooks, and mesh peer display state.
5. `epic-bold-split-pi-extension-index-owner-multiplexer-module-step-5` — lock compatibility exports and tests.

## Module shape
- **New module**: `pi-extension/src/extension/owner_multiplexer.ts`.
- **Implements**: `OwnerMultiplexerPort` from the composition-root boundary.
- **Private state**: owner channel map, last owner short id, late-attach owner set, machine-global pairing cache, owner-visible mesh session name/count projection.
- **Injected dependencies**: channel factory (`PlainPeerChannel` adapter), pairing storage (`listPeers`/`addPeer`/`removePeer` callers), QR token consumer, pair-ok builder/session snapshot provider, route-to-session callback, notification/footer callbacks, current relay-room snapshot.
- **Does not own**: relay websocket auth/reconnect/liveness, Pi SDK session context, message buffer/history projection, command registration, `MeshNode` socket/bridge lifecycle, or generated protocol schemas.

## Convention-driven steps
No project-specific `.agents/skills/refactor-conventions/` catalog exists. The plan uses default refactor-design lenses plus repo rules: ports/adapters, single source of truth, fail-fast boundary decoding, lifecycle ownership, and test integrity.

## Atomic steps acknowledged
No step intentionally changes public protocol, relay frame shape, CLI command names, or persisted `peers.json` semantics. Step 3 is the only semi-atomic behavioral route change because pair/known/unknown ingress and first-message replay must move together to avoid token or duplicate-routing regressions; rollback is still a single-step restore to the legacy listener.

## Risk and rollback summary
- Highest risks: duplicate relay listeners on reattach, reverting to a singleton Owner channel, consuming pair tokens on stale runtimes, routing the first reconnect message twice, or making footer/status projections stale.
- Rollback is step-local. Steps first add a shell, then move channel registry, then ingress, then projections, then test aliases. If a later step fails, revert that step while keeping earlier extraction if tests pass.
- Observable behavior remains pinned by existing multi-owner tests: N Owners attach, broadcasts reach every Owner, sender-specific replies stay sender-only, and revoking/disconnecting one Owner leaves others running.


## Review — advanced to done (2026-06-30)

All 5 child steps `done` (channel registry/fanout → owner ingress/pairing/reconnect
→ lifecycle projections/revocation → test harness + unit tests). The owner-channel
registry, fanout, pairing, reconnect, revocation, and display projections are now
behind `OwnerMultiplexer`; `index.ts` test exports delegate through a harness.
Epic complete.
