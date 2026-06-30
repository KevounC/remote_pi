---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module
kind: feature
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Split pi-extension index — SDK session projection module

## Brief
`_messageBuffer` / `_sessionStartedAt` / turn wiring extracted from `index.ts`
as a named module that projects from the canonical-session and
turn-state-machine epics. Globals `_sessionStartedAt`, `_messageBuffer`,
`_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`,
`_queuedMessage` (`index.ts:408-424`, `:538-544`) become this module's private
state — or, where the turn-state-machine epic has already named them, delegate
to it.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`; overlaps with
  `epic-bold-turn-state-machine` (the turn globals move there, this module
  holds the rest).

## Foundation references
- Evidence: `pi-extension/src/index.ts:408-424`, `:538-544`, `:1355-1625`,
  `:1446-1470`, `:3538-3590`.

## Absorbed from `story-investigate-model-thinking-actions-after-session-replacement` (retired 2026-06-29)

The retired investigation pinned a concrete consequence of the module-level
`_pi` global: after app-triggered `session_new`, valid app `model_set` and
`thinking_set` actions may return `action_error` until a full reload/restart,
because they route through stale `_pi.setModel()` / `_pi.setThinkingLevel()`
while the prompt path has a fresh `_messageApi`. The SDK-session-projection
module must expose fresh model/thinking setters on the replacement context (or
a fresh action-API wrapper) — not route through a stale module global. If the
SDK cannot expose fresh setters on `ReplacedSessionContext` / `session_start`,
this module records the SDK gap and degrades explicitly.

## Absorbed from `story-fix-cross-pc-bridge-late-attach-after-shutdown` (retired 2026-06-29)

The retired story pinned an async-teardown race in `MeshNode.attachBridge()` /
`attachCrossPcBridge()`: a `PiForwardClient` can be constructed, await sibling
discovery, and install `BrokerRemote` listeners *after* `MeshNode.close()` or
session shutdown if teardown lands during the async discovery window —
creating stale cross-PC routing state / ghost listeners. The SDK-session-
projection module (and the relay-transport module's teardown) must enforce a
post-await closed/epoch check on every bridge-attach continuation; `BrokerRemote
.handleIncoming`, `PlainPeerChannel`, and `PiForwardClient` must carry internal
detached guards, not rely solely on listener removal/upstream detach.

<!-- /agile-workflow:refactor-design pins the module boundary. -->

## Design decisions
- Autopilot judgment mode: treat this as a pure, fork-private structural split. Wire names, CLI commands, current app messages, relay routing, and user-visible behavior are preserved; stale-context failures are made explicit rather than silently continuing through stale SDK objects.
- Dispatch rationale: direct-read design in this nested worker. This harness instance exposes no subagent dispatcher, so exploratory fan-out was not available; the design is grounded in direct reads of foundation docs, `.agents/rules`, the pi-extension stack reference, sibling designs, `index.ts`, `session/bridge.ts`, transport/session helpers, and existing lifecycle tests.
- Module location: create `pi-extension/src/session/sdk_session_projection.ts` as the concrete implementation of the composition-root `SdkSessionProjectionPort`. It is a session projection module, not a transport or owner module.
- Port posture: the module may depend outward only through injected outputs (`broadcast`, `sendTo`, `publishRoomMeta`, `activeOwnerIds`, `lateAttachTargets`). It must not import the owner multiplexer concrete map or the relay transport concrete singleton.
- Session identity authority: this module owns `RemoteSessionIssuer` capture from `ctx.sessionManager.getSessionId()`. The existing `session/remote_session.ts` helper remains the identity primitive; this module becomes the runtime host that decides when to capture, clear, and publish the id.
- Turn coordination: the pure turn reducer from `epic-bold-turn-state-machine-algebraic-state` lives under `pi-extension/src/session/turn_state.ts`; this module owns the reducer snapshot for the current Pi session and derives `working`, cancel target, late-sync id, and queue-drain eligibility from its projection.
- Stale SDK context guard: SDK objects are stored by capability and epoch, not as one `_pi` global. Prompt delivery, custom messages, compact/cancel, model/thinking/list-models, and `newSession` each ask the freshest capability binding. A stale-context exception clears only the bad binding and retries/fails explicitly.
- Model/thinking after replacement: `withSession` recapture tries to bind fresh model/thinking setters if the SDK exposes them on the replacement context. If no current action API with `setModel`/`setThinkingLevel` exists, `model_set`/`thinking_set` return an explicit `action_error`/`error` explaining the missing current SDK action API; they never route through a known-stale pre-replacement `_pi`.
- Late bridge attach guard: this feature owns the epoch/detached guard shape because the bridge race is session-replacement-triggered. The relay-transport sibling can later move transport lifecycle code behind the same guard without changing the semantics.
- Patchbay migration guard: the module is named by generic host responsibility (`SdkSessionProjection`) and exposes an opaque `RemoteSession`/turn projection boundary. No cwd-derived, relay-derived, or Remote-Pi-fork-specific identity is baked into a schema in a way that would block patchbay from replacing the SDK adapter later.
- Cycle check: `.work/bin/work-view --blocking` is not present in this checkout, so cycle prevention was done by frontmatter scan. No existing `sdk-session-projection-module-step-*` stories exist. Step 1 depends on the composition-root feature; steps 2-5 form a forward chain. Step 4 also depends on `epic-bold-turn-state-machine-algebraic-state-step-1` because it consumes the reducer; that story does not depend back on this feature. No cycle is introduced.

## Refactor Overview
`pi-extension/src/index.ts` currently owns three different session concepts at once: Pi SDK context freshness (`_pi`, `_messageApi`, `_lastCtx`, `_lastEventCtx`), the Remote Pi session projection (`_sessionStartedAt`, `_messageBuffer`, `RemoteSessionIssuer`, `pair_ok`/`session_sync` snapshots), and the turn/queue lifecycle (`_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`, `_queuedMessage`, late-attach set). Those concerns are coupled only because the file is a god module.

This refactor extracts the SDK-facing projection into one module that implements the composition-root `SdkSessionProjectionPort`. `index.ts` keeps hook registration until the composition-root feature lands, but the hook bodies delegate to the session module. The owner multiplexer remains responsible for owner channels and fanout; relay transport remains responsible for WebSocket state; this module owns what the current Pi session *means* and which SDK object is safe to call.

The highest-risk behavior is stale context after session replacement. Today prompt sending was partially repaired by recapturing `_messageApi` from `withSession`, while model/thinking still route through `_pi`. The target module replaces that split with a single capability binding table and epoch. After `/new`, `/resume`, `/fork`, `/reload`, or daemon fresh-session restart, old contexts are invalidated before async continuations resume, and app actions either use the fresh capability or fail with a sender-scoped explicit error.

## Refactor Steps

### Step 1: Introduce the SDK session projection module shell
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / code smell
**Files**: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension/ports.ts`
**Story**: `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-1`

**Current State**:
```ts
// pi-extension/src/index.ts
let _pi: ExtensionAPI | null = null;
let _messageApi: AgentMessageApi | null = null;
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort" | "ui"> | null = null;
const _noopCtx = { ui: { notify: () => undefined }, abort: () => undefined };
```

**Target State**:
```ts
// pi-extension/src/session/sdk_session_projection.ts
export interface SdkSessionProjectionOutputs {
  broadcast(message: ServerMessage): void;
  sendTo(sender: PeerChannel, message: ServerMessage): void;
  publishRoomMeta(patch: { session_id?: string; model?: string; thinking?: ThinkingLevel; working?: boolean }): void;
  activeOwnerIds(): readonly string[];
  lateAttachTargets(): readonly { peerId: string; channel: PeerChannel }[];
}

export interface SdkSessionProjectionOptions {
  outputs: SdkSessionProjectionOutputs;
  now?: () => number;
  randomId?: () => string;
}

export class SdkSessionProjection implements SdkSessionProjectionPort {
  private epoch = 0;
  private commandCtx: ActionCtx | null = null;
  private eventCtx: ActionCtx | null = null;
  private messageApi: AgentMessageApi | null = null;
  private actionApi: FreshActionApi | null = null;

  constructor(private readonly opts: SdkSessionProjectionOptions) {}

  bindApi(pi: ExtensionAPI): void { this.bindCapabilities(pi); }
  bindCommandContext(ctx: ExtensionCommandContext): void { this.commandCtx = ctx; this.bindCapabilities(ctx); }
  bindSessionContext(ctx: ExtensionContext): void { this.eventCtx = ctx; this.captureRemoteSession(ctx); }
  clearStaleContexts(): void { this.epoch++; this.commandCtx = null; this.eventCtx = null; this.messageApi = null; this.actionApi = null; }
}
```

**Implementation Notes**:
- Add the module shell and move only capability binding helpers first; leave behavior delegated from `index.ts` through a singleton/wrapper so this step stays buildable.
- If `extension/ports.ts` does not exist yet, keep a local structural interface in this module and remove it when the composition-root story lands. Do not block on concrete composition-root files during this module's implementation.
- Capabilities are tested structurally (`sendUserMessage`, `sendMessage`, `setModel`, `setThinkingLevel`, `newSession`, `compact`, `abort`, `modelRegistry`, `getModel`, `sessionManager`). Avoid `any`; use `unknown` + narrowing.

**Acceptance Criteria**:
- [ ] `SdkSessionProjection` (or equivalently named module) exists under `pi-extension/src/session/` and satisfies the composition-root `SdkSessionProjectionPort` shape.
- [ ] `index.ts` no longer declares the fresh-context/message/action API binding helpers as raw globals; it delegates to the module or a thin singleton adapter.
- [ ] Existing prompt delivery, custom message, compact, cancel, model/thinking, and list-models behavior is unchanged.
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.

**Rollback**: Delete `sdk_session_projection.ts` and restore the context/API binding globals and helper functions in `index.ts`.

---

### Step 2: Move RemoteSession identity and transcript snapshot into the module
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / single source of truth
**Files**: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/session/remote_session.ts`, `pi-extension/src/index.ts`, `pi-extension/src/session/remote_session.test.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-2`

**Current State**:
```ts
// pi-extension/src/index.ts
let _sessionStartedAt: number | null = null;
const _remoteSessionIssuer = new RemoteSessionIssuer();
let _messageBuffer: BufferMsg[] = [];

function _captureRemoteSession(ctx: unknown): string {
  const sessionId = _remoteSessionIssuer.capture(ctx);
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, session_id: sessionId };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { session_id: sessionId } });
  }
  return sessionId;
}
```

**Target State**:
```ts
// pi-extension/src/session/sdk_session_projection.ts
export interface SessionHistorySnapshot {
  sessionStartedAt: number;
  sessionId: RemoteSessionId;
  queued: Extract<ServerMessage, { type: "queued_message_state" }>;
  history(inReplyTo: string, limit?: number): Extract<ServerMessage, { type: "session_history" }>;
}

export class SdkSessionProjection implements SdkSessionProjectionPort {
  private readonly issuer = new RemoteSessionIssuer();
  private sessionStartedAt: number | null = null;
  private messageBuffer: BufferMsg[] = [];

  captureRemoteSession(ctx: unknown): RemoteSessionId {
    const sessionId = this.issuer.capture(ctx);
    this.opts.outputs.publishRoomMeta({ session_id: sessionId });
    return sessionId;
  }

  currentRemoteSessionId(ctx?: unknown): RemoteSessionId {
    return this.issuer.currentOrCapture(ctx ?? this.eventCtx ?? this.commandCtx ?? undefined);
  }

  recordMessage(message: unknown): void {
    const m = normalizeBufferMessage(message);
    if (m) this.messageBuffer.push(m);
  }

  buildSessionHistory(inReplyTo: string, limit?: number): Extract<ServerMessage, { type: "session_history" }> {
    const events = mapAgentMessagesToEvents(this.messageBuffer);
    return { type: "session_history", in_reply_to: inReplyTo, session_started_at: this.sessionStartedAt ?? 0, events, eos: true, truncated: false };
  }
}
```

**Implementation Notes**:
- Keep `session/remote_session.ts` as the canonical identity helper from the canonical-session work; this module owns the runtime instance and publication timing.
- Move `BufferMsg`, `_mapAgentMessagesToEvents`, `session_sync`, compaction history marker, and `session_new` reset ownership here. `index.ts` should ask the module for `pair_ok` fields and session-sync replies instead of reading globals.
- Preserve stop/start semantics: relay stop/start preserves `sessionStartedAt` and `messageBuffer`; Pi SDK session replacement resets both.
- Keep `session_id` opaque. Do not derive it from room id, cwd, name, timestamp, or relay state.

**Acceptance Criteria**:
- [ ] `RemoteSessionIssuer`, `sessionStartedAt`, and transcript buffer are private to the projection module.
- [ ] `pair_ok`, `room_meta`, reconnect hello metadata, and `session_sync` all obtain `session_id`/history from the module.
- [ ] Tests prove `session_id` is captured from `ctx.sessionManager.getSessionId()`, preserved across relay reconnect, and recaptured on session replacement.
- [ ] Tests prove session history is preserved across relay stop/start and reset only after successful `session_new` / replacement.
- [ ] `corepack pnpm typecheck` and targeted `corepack pnpm test -- remote_session extension` pass from `pi-extension/`.

**Rollback**: Move `RemoteSessionIssuer`, `sessionStartedAt`, `messageBuffer`, and history helpers back into `index.ts`; remove the module history API.

---

### Step 3: Move app action routing behind fresh SDK capability guards
**Priority**: High
**Risk**: High
**Source Lens**: lifecycle ownership / fail-fast boundary
**Files**: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/actions/handlers.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/actions/handlers.test.ts`
**Story**: `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-3`

**Current State**:
```ts
// pi-extension/src/index.ts
case "model_set":
  if (!_pi) {
    _sessionUnavailable(sender, msg.id, "Pi model API unavailable during session replacement");
    break;
  }
  void handleModelSet(_pi, (_lastEventCtx ?? _lastCtx) as ActionCtx | null, ensureModelRegistry(), sender, msg, _persistModelDefault);
  break;
case "thinking_set":
  if (!_pi) {
    _sessionUnavailable(sender, msg.id, "Pi thinking API unavailable during session replacement");
    break;
  }
  handleThinkingSet(_pi, sender, msg);
  break;
```

**Target State**:
```ts
// pi-extension/src/session/sdk_session_projection.ts
type FreshActionApi = AgentMessageApi & Partial<ActionPi> & Partial<ActionCtx>;

private bindCapabilities(value: unknown): void {
  if (isAgentMessageApi(value)) this.messageApi = value;
  if (isActionPi(value)) this.actionApi = { ...(this.actionApi ?? {}), ...value };
  if (isActionCtx(value)) {
    this.eventCtx = { ...(this.eventCtx ?? {}), ...value };
    if (isActionPi(value)) this.actionApi = { ...value, ...this.eventCtx };
  }
}

private currentActionPi(action: "model_set" | "thinking_set"): ActionPi | null {
  if (!this.actionApi) return null;
  if (action === "model_set" && typeof this.actionApi.setModel === "function") return this.actionApi as ActionPi;
  if (action === "thinking_set" && typeof this.actionApi.setThinkingLevel === "function") return this.actionApi as ActionPi;
  return null;
}

handleClientMessage(sender: PeerChannel, msg: ClientMessage): void {
  if (this.isDisposed()) return this.sessionUnavailable(sender, msg.id);
  switch (msg.type) {
    case "session_new":
      void handleSessionNew(this.commandCtx, sender, msg, (freshCtx) => this.bindReplacementContext(freshCtx));
      return;
    case "model_set": {
      const pi = this.currentActionPi("model_set");
      if (!pi) return this.sessionUnavailable(sender, msg.id, "Pi model API unavailable for the current session");
      void handleModelSet(pi, this.freshActionCtx(), ensureModelRegistry(), sender, msg, this.persistModelDefault);
      return;
    }
    case "thinking_set": {
      const pi = this.currentActionPi("thinking_set");
      if (!pi) return this.sessionUnavailable(sender, msg.id, "Pi thinking API unavailable for the current session");
      handleThinkingSet(pi, sender, msg);
      return;
    }
  }
}
```

**Implementation Notes**:
- `session_new` remains command-context-only. `withSession` recapture must bind fresh command ctx, event ctx, message API, action API if present, and session id in one place.
- Prompt delivery (`wakeAgent`) uses the same stale-context retry loop as custom message delivery (`sendPiMessage`), but model/thinking must not fall back to a known-stale `_pi`.
- If the Pi SDK does not expose `setModel`/`setThinkingLevel` on replacement/session-start contexts, document that in the code comment and return a clear sender-scoped error. Do not hide it by touching a stale API.
- Keep `actions/handlers.ts` pure/dependency-injected; this step changes the caller/adapter, not the handler contract unless a narrower `ActionPi` type is needed.

**Acceptance Criteria**:
- [ ] App `session_new` recaptures fresh capabilities in one module method.
- [ ] App prompt after `session_new` uses the fresh message API and never calls the stale API.
- [ ] App `model_set` and `thinking_set` after replacement use a fresh action API when the SDK exposes one, or return an explicit sender-scoped unavailable error without calling stale `_pi`.
- [ ] `cancel` and `session_compact` prefer the freshest `session_start`/replacement context and clear stale bindings on stale-context exceptions.
- [ ] Targeted stale-context tests cover prompt, compact/cancel, model, thinking, and list-models paths after `/new`/`/resume`/`/fork`/`/reload` simulation.
- [ ] `corepack pnpm typecheck` and targeted `corepack pnpm test -- extension actions` pass from `pi-extension/`.

**Rollback**: Restore app action routing in `index.ts` and the prior `_pi`/`_lastCtx`/`_lastEventCtx` helper paths; keep the module shell unused if necessary.

---

### Step 4: Move turn, queue, and late-attach state into the projection module
**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction / lifecycle convergence
**Files**: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/session/turn_state.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/turn_state.test.ts`
**Story**: `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-4`

**Current State**:
```ts
// pi-extension/src/index.ts
let _currentTurnId: string | null = null;
let _turnActive = false;
let _finishedTurnIdAwaitingSync: string | null = null;
const _peersAttachedDuringTurn = new Set<string>();
let _queuedMessage: QueuedMessage | null = null;

function _maybeDrainQueuedMessage(): void {
  if (!_queuedMessage || _turnActive || _currentTurnId !== null) return;
  const queued = _queuedMessage;
  _queuedMessage = null;
  _broadcastQueuedMessageState();
  void _deliverUserMessage({ type: "user_message", id: queued.id, text: queued.text }, null, "normal");
}
```

**Target State**:
```ts
// pi-extension/src/session/sdk_session_projection.ts
export class SdkSessionProjection implements SdkSessionProjectionPort {
  private turn = initialTurnSnapshot();

  onPiInput(event: { text: string; source?: string }): void {
    if (event.source === "extension") return;
    const projection = this.applyTurn({ type: "local_input", fallbackTurnId: `local_${this.randomId()}` });
    this.opts.outputs.broadcast({ type: "user_input", id: projection.activeTurnId!, text: event.text });
  }

  onMessageUpdate(event: MessageUpdateEventLike): void {
    const turn = projectTurn(this.turn).activeTurnId;
    if (!turn) return;
    this.applyTurn({ type: "agent_chunk", turnId: turn });
    this.opts.outputs.broadcast({ type: "agent_chunk", in_reply_to: turn, delta: event.delta });
  }

  private applyTurn(event: TurnEvent): TurnProjection {
    const before = projectTurn(this.turn);
    this.turn = reduceTurn(this.turn, event);
    const after = projectTurn(this.turn);
    if (before.working !== after.working) this.opts.outputs.publishRoomMeta({ working: after.working });
    return after;
  }
}
```

**Implementation Notes**:
- This step depends on `epic-bold-turn-state-machine-algebraic-state-step-1` because the reducer must exist before this module owns a reducer snapshot.
- Preserve current wire behavior: still send `user_input`, `agent_chunk`, `agent_done`, `tool_request`, `tool_result`, `compaction`, `queued_message_state`, and `session_history`; do not introduce a new turn-state wire message.
- Late-attach peers are selected through the owner-output port (`lateAttachTargets` / `activeOwnerIds`) rather than by reaching into `_activePeers`.
- Queue drain uses the reducer projection (`canDrainQueuedMessage`) instead of checking `_turnActive` and `_currentTurnId` manually.
- `working` is derived from the reducer projection and published through the injected room-meta output; duplicate false patches are acceptable, stuck true is not.

**Acceptance Criteria**:
- [ ] `_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`, `_peersAttachedDuringTurn`, and `_queuedMessage` are removed from `index.ts` and owned by `SdkSessionProjection`/`turn_state`.
- [ ] Existing behavior for app prompts, steer behavior, local terminal input, agent chunks/done, tool visibility, compaction marker replay, queued prompt set/clear/drain, and late-owner attach is preserved.
- [ ] Tests prove `working:false` convergence after success, provider error, cancel/abort, compaction, session replacement/shutdown, relay reconnect, and late attach recovery.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test -- turn_state`, and targeted `corepack pnpm test -- extension` pass from `pi-extension/`.

**Rollback**: Move turn/queue/late-attach fields and helper functions back into `index.ts`; keep the reducer module from the turn-state feature if already landed.

---

### Step 5: Harden session epoch teardown and cross-PC bridge late continuations
**Priority**: High
**Risk**: Medium
**Source Lens**: lifecycle ownership / dead weight prevention
**Files**: `pi-extension/src/session/sdk_session_projection.ts`, `pi-extension/src/session/bridge.ts`, `pi-extension/src/session/mesh_node.ts`, `pi-extension/src/session/broker_remote.ts`, `pi-extension/src/transport/peer_channel.ts`, `pi-extension/src/transport/pi_forward_client.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/broker_remote.test.ts`
**Story**: `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-5`

**Current State**:
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

**Target State**:
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

**Implementation Notes**:
- `SdkSessionProjection.clearStaleContexts()` increments the session epoch before any awaited teardown. Bridge attach paths receive an epoch/current predicate from their owning transport/session root.
- Add detached guards to `PlainPeerChannel.send`, `PlainPeerChannel._onLine`, `BrokerRemote.handleIncoming`, and `PiForwardClient._handleLine` so an already-detached object no-ops even if an event was already queued.
- This step should not change relay protocol, peer address format, or cross-PC authorization. It only prevents stale listeners from installing or acting after shutdown.
- Relay-transport extraction can later move this guard into its own module; the guard contract should remain generic (`isCurrent` / epoch), not tied to the current god-file globals.

**Acceptance Criteria**:
- [ ] A `MeshNode.attachBridge()` / `attachCrossPcBridge()` continuation that resumes after `detachBridge()`, `MeshNode.close()`, or `session_shutdown` detaches any partial `PiForwardClient` and does not install `BrokerRemote`.
- [ ] `PlainPeerChannel`, `BrokerRemote`, and `PiForwardClient` ignore sends/inbound events after `detach()`.
- [ ] Existing cross-PC routing tests still pass; new regression tests cover late attach after shutdown and detached inbound event no-op.
- [ ] `corepack pnpm typecheck` and targeted `corepack pnpm test -- extension broker_remote` pass from `pi-extension/`.

**Rollback**: Remove the epoch/current predicate and detached guards, restoring the previous attach flow. If rollback is necessary, keep a follow-up bug because this reopens the ghost-listener race.

## Implementation Order
1. `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-1` — introduce the module shell and capability binding seam; depends on `epic-bold-split-pi-extension-index-composition-root`.
2. `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-2` — move `RemoteSessionIssuer`, `sessionStartedAt`, transcript buffer, and session-sync/history projection into the module.
3. `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-3` — route app actions and prompt delivery through fresh SDK capability guards, including model/thinking after session replacement.
4. `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-4` — move turn/queue/late-attach state into the module and consume the turn reducer from `epic-bold-turn-state-machine-algebraic-state-step-1`.
5. `epic-bold-split-pi-extension-index-sdk-session-projection-module-step-5` — harden session epoch teardown and cross-PC bridge late continuations.

## Convention-driven steps
No project-specific `.agents/skills/refactor-conventions/` catalog exists. The plan uses the default refactor-design lenses plus Remote Pi rules: ports/adapters, single source of truth, fail-fast boundaries, lifecycle ownership, convergent state, and test integrity.

## Atomic steps acknowledged
No step intentionally changes public protocol shape or CLI API. Step 3 is semi-atomic because app action dispatch and capability binding must move together to avoid falling back to stale `_pi`; rollback is restoring the old router. Step 4 is semi-atomic because hook events, turn projection, queued drain, and late attach all share one reducer snapshot; rollback is restoring the current nullable/boolean state block in `index.ts`. Step 5 is rollbackable but reopens a known ghost-listener race if backed out.

## Risk and rollback summary
- Highest risk: using a fresh SDK capability when Pi replaces sessions. The module guards this by epoch + capability checks and by clearing stale bindings on the SDK's stale-context error string.
- Medium risk: moving `session_sync` history into a module while preserving stop/start vs. session-replacement semantics. Tests must prove relay reconnect does not reset history and successful `session_new` does.
- Medium risk: bridge attach guard touching cross-PC code. The guard is additive/no-op when current; detached objects already conceptually should no-op.
- Rollback is step-local because the module is introduced as a shell, then owns identity/history, then action routing, then turn state, then late continuation guards.

## Review — advanced to done (2026-06-30)

All 5 child steps `done` (session identity/transcript → app ingress/action routing
→ fresh-capability guards → turn/queue/late-attach state → epoch teardown + bridge
late-continuation). `index.ts` no longer owns session identity, transcript history,
turn/queue/late-attach state, or stale `_pi` fallback — all moved into
`SdkSessionProjection`. `working:false` convergence preserved across all 7 paths.
Detached no-op guards harden the cross-PC bridge against late continuations. Epic complete.
