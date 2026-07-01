---
id: epic-bold-turn-state-machine-late-attach
kind: feature
stage: done
tags: [refactor, bold, pi-extension, app]
parent: epic-bold-turn-state-machine
depends_on: [epic-bold-turn-state-machine-algebraic-state]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Turn — late-attach as the Done(awaitingSync) state

## Brief
`_finishedTurnIdAwaitingSync` (`pi-extension/src/index.ts:540`) is a *named
state* pretending to be a nullable string today — a special-case latch bridging
late-attaching owners after `agent_end`. Make it the `Done(awaitingSync)` state
of the canonical `Turn`; late-attaching owners hydrate from that state instead
of a special-case nullable. Retires the late-attach sync workaround
(`index.ts:3324-3337`).

## Epic context
- Parent epic: `epic-bold-turn-state-machine`
- Position: consumer of `algebraic-state`. Resolves the late-attach story
  (`story-fix-late-attach-turn-stream-sync`, `story-fix-cross-pc-bridge-late-attach-after-shutdown`)
  structurally rather than as patches.

## Foundation references
- Evidence: `pi-extension/src/index.ts:540`, `:1476-1484`, `:3324-3337`.

## Absorbed from `story-fix-cross-pc-bridge-late-attach-after-shutdown` (retired 2026-06-29)

The retired story's late-attach race (bridge attaches relay/broker listeners
after teardown) is one instance of the broader late-attach pattern the
`Done(awaitingSync)` state absorbs: an async continuation completing after the
owning lifecycle has closed. The `Done(awaitingSync)` transition must cover
not only late-attaching *owners* but any late-completing continuation whose
owning context may have torn down — the state is "awaiting sync" precisely
because the continuation may still land.

<!-- /agile-workflow:refactor-design pins the Done(awaitingSync) transition. -->

## Refactor Overview

Late attach is currently a special-case lifecycle seam outside the turn model:
`pi-extension/src/index.ts` mutates `_turnActive`, `_peersAttachedDuringTurn`,
and `_finishedTurnIdAwaitingSync` directly, then hand-flushes a targeted
`session_history` after `agent_end`/`turn_end`. That works for one happy path but
keeps the "done but not fully synchronized" state in a nullable string instead
of the canonical turn reducer. The same late-attach shape also appears in the
cross-PC bridge: `MeshNode.attachBridge()` can finish async sibling discovery and
install relay/broker listeners after the owning node has been detached or closed.

Target state: the algebraic turn reducer owns late attach. `peer_attached` records
late owners/tools in `TurnSnapshot`, terminal success moves to `Done(awaitingSync)`
with `working:false`, and a projection exposes `awaitingSyncTurnId`,
`lateAttachSyncTargets`, `canFlushLateAttachSync`, and `canDrainQueuedMessage`.
`index.ts` consumes those selectors instead of maintaining its own latch. The
mobile app keeps the existing wire (`room_meta.working`, `agent_chunk`,
`agent_done`, `session_history`); tests prove that a late-attaching app hydrates
`working:true` while active and converges to `working:false` after done, sync,
queued drain, and shutdown. No new `turn_state` wire message is introduced, so
this fork-private refactor does not block generated-protocol or future patchbay
migration.

### Scan findings and rationale

- **Code smell: named state hidden as nullable latch.** `_finishedTurnIdAwaitingSync`
  is exactly `Done(awaitingSync)`, but it is independent of `_turnActive`,
  `_currentTurnId`, and queue drain checks.
- **Missing abstraction: late targets live outside the reducer.**
  `_peersAttachedDuringTurn` is already promised as part of `TurnSnapshot` by the
  algebraic-state sibling; leaving it mutable in `index.ts` would recreate the
  same two-source state machine.
- **Lifecycle ownership gap: cross-PC bridge attach can outlive its owner.**
  `attachCrossPcBridge()` awaits sibling discovery before returning concrete
  listener-owning objects; `MeshNode` needs an epoch/closed guard before retaining
  them.
- **Pattern drift: app hydration has symptom tests, not a late-attach matrix.**
  `ConnectionManager` and `SyncService` already contain working-state correction
  paths, but late `session_history` replay must be explicitly proved not to
  resurrect working/cancel state after terminal false.
- **Not worth doing here:** a new cross-language `turn_state` protocol frame or
  app-wide projection rewrite. Those belong to generated-protocol / projection-
  consumers / patchbay work.

### Coordination / cycle check

`.work/bin/work-view --blocking` is not present in this checkout, so the cycle
check was performed by frontmatter scan before writing: no active item referenced
any `epic-bold-turn-state-machine-late-attach-step-*` id, and the feature already
depended only on `epic-bold-turn-state-machine-algebraic-state`. The emitted
child stories form this acyclic chain:

`epic-bold-turn-state-machine-algebraic-state -> late-attach-step-1 -> late-attach-step-2 -> late-attach-step-3 -> late-attach-step-4`.

## Refactor Steps

### Step 1: Put late-attach collection into `TurnSnapshot`
**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / code smell  
**Files**: `pi-extension/src/session/turn_state.ts`, `pi-extension/src/session/turn_state.test.ts`  
**Story**: `epic-bold-turn-state-machine-late-attach-step-1`

**Current State**:
```ts
// pi-extension/src/index.ts
let _finishedTurnIdAwaitingSync: string | null = null;
const _peersAttachedDuringTurn = new Set<string>();

function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
  if (_turnActive) _peersAttachedDuringTurn.add(appPeerId);
}
```

**Target State**:
```ts
export type LateAttachKind = "owner" | "mesh_bridge";
export interface LateAttachTarget { kind: LateAttachKind; id: string }

export type TurnEvent =
  | { type: "peer_attached"; target: LateAttachTarget }
  | { type: "agent_done" }
  | { type: "turn_end" }
  | { type: "flush_late_attach_sync" }
  | ExistingTurnEvent;

export interface TurnProjection {
  working: boolean;
  replyTo: string | null;
  activeTurnId: string | null;
  awaitingSyncTurnId: string | null;
  lateAttachSyncTargets: readonly LateAttachTarget[];
  canFlushLateAttachSync: boolean;
  canDrainQueuedMessage: boolean;
}
```

**Implementation Notes**:
- Extend the algebraic-state sibling's reducer; do not introduce a parallel late-attach registry.
- Keep the reducer pure: no channels, relay clients, brokers, Pi SDK contexts, timers, or logging.
- `Done(awaitingSync)` projects `working:false`; catch-up sync must never look like an active turn.
- Deduplicate repeated late owner attach events by id.

**Acceptance Criteria**:
- [ ] `corepack pnpm test -- turn_state` passes from `pi-extension/`.
- [ ] Reducer tests cover owner attach during `Working`, `Streaming`, and `AwaitingTool`.
- [ ] Reducer tests cover `agent_done -> Done(awaitingSync)` collecting late targets while projecting `working:false`.
- [ ] Reducer tests cover `turn_end + flush_late_attach_sync` clearing targets and allowing queued drain.
- [ ] Reducer tests cover `session_shutdown` clearing targets and projecting `working:false`.
- [ ] No reducer state stores concrete channels or lifecycle-owned resources.

**Rollback**: Revert the late-attach event/projection additions and tests. The base algebraic reducer can remain.

---

### Step 2: Route owner attach and late sync through the turn projection
**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / missing abstraction  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/turn_state.ts`, `pi-extension/src/extension.test.ts`  
**Story**: `epic-bold-turn-state-machine-late-attach-step-2`

**Current State**:
```ts
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
  // send session_history to each late owner channel
}
```

**Target State**:
```ts
function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
  _applyTurn({ type: "peer_attached", target: { kind: "owner", id: appPeerId } });
}

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

**Implementation Notes**:
- Remove `_finishedTurnIdAwaitingSync` and direct `_peersAttachedDuringTurn` mutation from `index.ts`.
- `_maybeDrainQueuedMessage` should use `projectTurn(_turn).canDrainQueuedMessage`.
- Preserve existing wire behavior: late owners still get chunks/done when attached before those frames and final `session_history` after terminal flush.
- Missing late target channels are skipped and cleared; they are not retry queues.

**Acceptance Criteria**:
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` and `corepack pnpm test -- turn_state` pass from `pi-extension/`.
- [ ] `index.ts` no longer has a nullable `_finishedTurnIdAwaitingSync` latch.
- [ ] Owner attach during an active local/RPC turn is represented by a reducer event.
- [ ] Late owner attach tests prove `agent_chunk`, `agent_done`, `session_history`, and `working:false` reach the late owner.
- [ ] A queued message drains only after late sync flush is safe.

**Rollback**: Revert `index.ts` and extension tests to the algebraic-state baseline; keep Step 1 unused if needed.

---

### Step 3: Guard cross-PC bridge late attach with a lifecycle epoch
**Priority**: High  
**Risk**: Medium  
**Source Lens**: lifecycle ownership / code smell  
**Files**: `pi-extension/src/session/mesh_node.ts`, `pi-extension/src/session/bridge.ts`, `pi-extension/src/session/mesh_node.test.ts` or focused existing session test file  
**Story**: `epic-bold-turn-state-machine-late-attach-step-3`

**Current State**:
```ts
const { brokerRemote, piForward } = await attachCrossPcBridge({
  broker,
  relay,
  relayUrl: params.relayUrl,
  keypair: this.keypair,
  log: this.log,
});
this.brokerRemote = brokerRemote;
this.piForward = piForward;
```

**Target State**:
```ts
private bridgeEpoch = 0;
private closed = false;

private _isBridgeEpochCurrent(epoch: number, params: BridgeParams, broker: Broker, relay: RelayClient): boolean {
  return !this.closed &&
    this.bridgeEpoch === epoch &&
    this.bridgeParams === params &&
    this.peer_.currentRole() === "leader" &&
    this.peer_.localBroker() === broker &&
    this.relay === relay;
}

const bridge = await attachCrossPcBridge({ broker, relay, relayUrl: params.relayUrl, keypair: this.keypair, log: this.log });
if (!this._isBridgeEpochCurrent(epoch, params, broker, relay)) {
  bridge.brokerRemote.detach();
  bridge.piForward.detach();
  return;
}
this.brokerRemote = bridge.brokerRemote;
this.piForward = bridge.piForward;
```

**Implementation Notes**:
- Increment the epoch on detach, close, failover reattach, and self-managed relay reconnect.
- If a stale continuation already constructed listeners, detach before returning.
- Do not close injected relays; `index.ts` remains their lifecycle owner.
- This is the bridge/tool form of the same late-attach class: an async attach may complete after the owner is terminal.

**Acceptance Criteria**:
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] A deterministic test parks bridge discovery, closes/detaches the node, releases discovery, and asserts `hasBridge()` remains false.
- [ ] The test asserts no relay envelope or broker-remote listeners remain after the stale continuation resolves.
- [ ] Existing cross-PC bridge/e2e tests still pass.
- [ ] Injected-relay callers still do not have their relay closed by `MeshNode`.

**Rollback**: Revert `mesh_node.ts`, `bridge.ts`, and the focused bridge late-attach test. Owner late-attach reducer work can remain.

---

### Step 4: Prove late-attach convergence across extension and app hydration
**Priority**: High  
**Risk**: Medium  
**Source Lens**: testing-integrity convergence requirement / pattern drift  
**Files**: `pi-extension/src/extension.test.ts`, `pi-extension/src/session/turn_state.test.ts`, `app/test/transport/connection_manager_working_test.dart`, `app/test/data/sync/sync_service_test.dart`, optionally `app/lib/data/transport/connection_manager.dart`  
**Story**: `epic-bold-turn-state-machine-late-attach-step-4`

**Current State**:
```ts
// Existing extension coverage pins one happy path:
// late owner attach during local/RPC turn receives chunk, done, history, and working=false.
```

```dart
bool isRoomWorking(String epk, String roomId) {
  if (_status is! StatusOnline) return false;
  // reads cached RoomInfo.working
}
```

**Target State**:
```ts
const lateAttachTerminalCases = [
  "agent_done_then_turn_end",
  "turn_end_before_flush",
  "session_shutdown_before_flush",
  "queued_message_after_late_sync",
] as const;
```

```dart
test('late attach hydrates working true then terminal false without session_history reviving it', () async {
  ch.pushControl(const RoomAnnounced(peer: 'epk_test', roomId: 'r1', startedAt: 1, working: true));
  expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);
  ch.pushControl(const RoomMetaUpdated(peer: 'epk_test', roomId: 'r1', working: false, hasModel: false, hasThinking: false));
  expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);
  // applying final session_history must not reopen working/cancel state
});
```

If tests expose cached offline rooms reporting working while not live, make the minimal projection correction:

```dart
bool isRoomWorking(String epk, String roomId) {
  if (!isRoomLive(epk, roomId)) return false;
  // then read RoomInfo.working
}
```

**Implementation Notes**:
- Use deterministic reducer/fake-channel tests and existing Flutter settle helpers; avoid arbitrary sleeps.
- Prove both active attach and post-done/pre-flush attach.
- `session_history` is catch-up data and must not resurrect active working or a cancel target after terminal false.
- Keep fixes limited to late-attach hydration/convergence; route broader consumer rewrites to `epic-bold-turn-state-machine-projection-consumers`.

**Acceptance Criteria**:
- [ ] `corepack pnpm test -- turn_state` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` passes from `pi-extension/`.
- [ ] `flutter test test/transport/connection_manager_working_test.dart test/data/sync/sync_service_test.dart` passes from `app/`.
- [ ] Tests prove `working:false`, null cancel target, and empty late target collection after success, late sync flush, queued drain, and shutdown.
- [ ] Tests prove app `session_history` replay after terminal false does not re-open active working.
- [ ] No new protocol shape is introduced.

**Rollback**: Revert added convergence tests and any minimal app projection correction. Do not weaken convergence assertions.

## Implementation Order

1. `epic-bold-turn-state-machine-late-attach-step-1` — extend the pure reducer/projection with late-attach targets and `Done(awaitingSync)` selectors.
2. `epic-bold-turn-state-machine-late-attach-step-2` — route owner attach, late sync flush, and queued drain in `index.ts` through those selectors.
3. `epic-bold-turn-state-machine-late-attach-step-3` — add lifecycle epoch guards to the cross-PC bridge attach path so stale async continuations cannot install after shutdown.
4. `epic-bold-turn-state-machine-late-attach-step-4` — run the late-attach convergence matrix across extension reducer/hook tests and app hydration tests.

## Refactor-design run notes

- Ambiguity resolved by judgment: "tools that attach mid-turn" maps to the cross-PC bridge/mesh attach continuation rather than a new app-visible protocol entity. The reducer tracks ids/kinds only; concrete bridge listener ownership is handled by `MeshNode` epochs.
- Ambiguity resolved by judgment: late sync is catch-up work in `Done(awaitingSync)` and always projects `working:false`; it must not become another active state.
- Ambiguity resolved by judgment: app changes here are tests or minimal projection corrections only. Full app/cockpit/relay consumer rewrites remain with `epic-bold-turn-state-machine-projection-consumers`.
- Dispatch rationale: no exploratory subagents were used because the target is a bounded set of lifecycle files (`index.ts`, `turn_state.ts` from the prior design, `mesh_node.ts`, `bridge.ts`, and app working hydration tests). Direct read-first scanning covered the mandatory lenses.
