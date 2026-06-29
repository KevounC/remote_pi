---
id: epic-bold-split-pi-extension-index-composition-root
kind: feature
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Split pi-extension index — composition root (riskiest — design first)

## Brief
The thin `index.ts` composition root + the four module interfaces (relay
transport, owner multiplexer, SDK session projection, CLI/daemon/pairing). The
module interface boundaries are what the split hangs on — they must be defined
before any module can be extracted, since the four concerns are genuinely
coupled through shared globals today.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: riskiest child — the interface boundaries are what the rest hangs
  on. Design FIRST.

## Foundation references
- Evidence: `pi-extension/src/index.ts:35-180` (imports + global state),
  `:1327-1619` (Pi SDK event wiring), `:1635-1688` (command dispatch),
  `:3217-3588` (client-message router).

<!-- /agile-workflow:refactor-design pins the module interfaces. -->

## Design decisions
- Autopilot judgment mode: treat this as a pure structure-preserving refactor. Public protocol, CLI command names/output, relay room semantics, app behavior, and test-only exports remain compatible during this feature.
- Dispatch rationale: direct-read design in this delegated sub-agent. The exposed tool surface for this sub-agent did not include a child-agent dispatcher, so no exploratory fan-out was possible; the design is grounded in direct reads of `index.ts`, `transport/`, `session/`, `actions/`, tests, foundation docs, and stack references. This is acceptable for the composition-root pass because the target is a single god file plus already-named neighboring modules.
- Composition root boundary: create an `extension/` (or `runtime/`) boundary layer whose only job is wiring Pi SDK hooks/commands to named ports. Do not move module internals into the root; sibling features will fill the four ports.
- Patchbay migration guard: ports are named by generic runtime responsibilities (`RelayTransportPort`, `OwnerMultiplexerPort`, `SdkSessionProjectionPort`, `CommandSurfacePort`) rather than Remote-Pi-specific implementation classes, so a future patchbay host can implement the same shape without inheriting today’s god-file globals.
- Cycle check for child stories: manual frontmatter scan found no existing `*-composition-root-step-*` stories. The chain is linear: step 1 → 2 → 3 → 4 → 5. The parent feature has no `depends_on`, and no child points back from an ancestor, so no dependency cycle is introduced.

## Refactor Overview
`pi-extension/src/index.ts` currently acts as extension factory, relay transport owner, owner-channel multiplexer, SDK session projection, command/daemon/pairing surface, local mesh bridge, and standalone CLI. The split epic cannot safely extract the four sibling modules until the seam between them is explicit. This feature therefore introduces a behavior-preserving composition root and type-level port registry first, then routes the existing `index.ts` callbacks through legacy adapters that satisfy those ports.

The target end state of this feature is not “all modules extracted.” The target is: `index.ts` has a clear top-level wiring shape; the four future modules have stable contracts to implement; stale Pi SDK context, session replacement, relay teardown, and late cross-PC bridge attach races are represented in those contracts via fresh-context and lifecycle-epoch ports.

## Refactor Steps

### Step 1: Define the runtime port registry
**Priority**: High
**Risk**: Medium
**Source Lens**: code smell / missing abstraction
**Files**: `pi-extension/src/extension/ports.ts`, `pi-extension/src/protocol/types.ts`, `pi-extension/src/transport/relay_client.ts`
**Story**: `epic-bold-split-pi-extension-index-composition-root-step-1`

**Current State**:
```ts
// pi-extension/src/index.ts
let _relay: RelayClient | null = null;
const _activePeers = new Map<string, PlainPeerChannel>();
let _sessionStartedAt: number | null = null;
let _messageBuffer: BufferMsg[] = [];
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;
let _lastEventCtx: Pick<ExtensionContext, "compact" | "abort" | "ui"> | null = null;
let _messageApi: AgentMessageApi | null = null;
```

**Target State**:
```ts
// pi-extension/src/extension/ports.ts
import type { ExtensionAPI, ExtensionCommandContext, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { ClientMessage, ServerMessage, ThinkingLevel, ByeReason } from "../protocol/types.js";
import type { RelayConnectivity } from "./types.js";
import type { RelayClient, RoomMeta } from "../transport/relay_client.js";
import type { PeerChannel } from "../transport/peer_channel.js";

export interface RuntimeEpoch {
  readonly id: number;
  readonly disposed: boolean;
  isCurrent(): boolean;
  dispose(): void;
}

export interface RuntimeUiPort {
  notify(message: string, type?: "info" | "warning" | "error"): void;
  setStatus(key: string, value: string | undefined): void;
  setTitle(title: string): void;
}

export interface RelayTransportPort {
  status(): RelayConnectivity;
  start(input: RelayStartInput): Promise<RelayStartResult>;
  stop(reason?: ByeReason): void;
  sendRoomMeta(patch: Partial<RoomMeta> & { working?: boolean; thinking?: ThinkingLevel }): void;
  onOuterMessage(handler: (line: string) => void | Promise<void>): () => void;
  attachCrossPcBridge(input: CrossPcBridgeInput): Promise<void>;
  detachCrossPcBridge(): void;
}

export interface OwnerMultiplexerPort {
  activeCount(): number;
  attach(input: AttachOwnerInput): PeerChannel;
  detach(peerId: string, reason?: ByeReason): void;
  broadcast(message: ServerMessage): void;
  routeFrom(sender: PeerChannel, message: ClientMessage): void;
  lateAttachTargets(): PeerChannel[];
}

export interface SdkSessionProjectionPort {
  bindApi(pi: ExtensionAPI): void;
  bindCommandContext(ctx: ExtensionCommandContext): void;
  bindSessionContext(ctx: ExtensionContext): void;
  clearStaleContexts(): void;
  sendPiMessage(...args: Parameters<ExtensionAPI["sendMessage"]>): boolean;
  wakeAgent(...args: Parameters<ExtensionAPI["sendUserMessage"]>): Promise<{ ok: true } | { ok: false; detail: string }>;
  publishWorking(working: boolean): void;
  handleClientMessage(sender: PeerChannel, message: ClientMessage): void;
}

export interface CommandSurfacePort {
  register(pi: ExtensionAPI, runtime: RemotePiRuntime): void;
}

export interface RemotePiRuntimePorts {
  relay: RelayTransportPort;
  owners: OwnerMultiplexerPort;
  session: SdkSessionProjectionPort;
  commands: CommandSurfacePort;
}
```

**Implementation Notes**:
- Keep this step type-first and side-effect free.
- Avoid importing concrete `index.ts` helpers into `ports.ts`. If a type currently lives only in `index.ts` (for example `RelayConnectivity`), move the type to a neutral `extension/types.ts`-style module in this step; do not create runtime cycles.
- Keep the room-meta shape aligned with `RelayClient` and `protocol/types.ts`; do not invent new wire fields.

**Acceptance Criteria**:
- [ ] `pi-extension/src/extension/ports.ts` (or equivalently named boundary file) defines the four module ports and runtime epoch contract.
- [ ] The port file compiles under ESM/NodeNext with `.js` imports where needed.
- [ ] No runtime behavior changes and no public protocol/CLI output changes.
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.

**Rollback**: Delete the new boundary file and remove any type-only imports added by this step.

---

### Step 2: Add the composition-root shell and lifecycle epoch
**Priority**: High
**Risk**: High
**Source Lens**: code smell / refactor convention: lifecycle ownership
**Files**: `pi-extension/src/extension/composition_root.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-composition-root-step-2`

**Current State**:
```ts
const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  _pi = pi;
  _messageApi = pi;
  _refreshPairingsCache();
  pi.on("resources_discover", () => ({ skillPaths: [skillsDir()] }));
  registerAgentTools(pi, () => _meshNode?.peer() ?? null);
  pi.on("input", (event) => { /* direct global mutation */ });
  // ...more Pi hooks...
  pi.registerCommand("remote-pi", { /* direct command router */ });
  if (process.env["REMOTE_PI_DAEMON"] === "1") {
    setTimeout(() => { void _cmdRoot(daemonCtx); }, 0);
  }
};
```

**Target State**:
```ts
// pi-extension/src/extension/composition_root.ts
import type { ExtensionAPI, ExtensionFactory } from "@earendil-works/pi-coding-agent";
import type { RemotePiRuntimePorts, RuntimeEpoch } from "./ports.js";

export interface RemotePiRuntime {
  readonly epoch: RuntimeEpoch;
  register(): void;
  dispose(): Promise<void>;
}

export function createRemotePiExtensionRuntime(
  pi: ExtensionAPI,
  ports: RemotePiRuntimePorts,
): RemotePiRuntime {
  const epoch = createRuntimeEpoch();
  return {
    epoch,
    register() {
      ports.session.bindApi(pi);
      ports.commands.register(pi, this);
      registerLifecycleHooks(pi, ports, epoch);
    },
    async dispose() {
      epoch.dispose();
      ports.session.clearStaleContexts();
      ports.relay.stop();
      ports.relay.detachCrossPcBridge();
    },
  };
}

export function createRemotePiExtensionFactory(
  createPorts: () => RemotePiRuntimePorts,
): ExtensionFactory {
  return (pi) => {
    const runtime = createRemotePiExtensionRuntime(pi, createPorts());
    runtime.register();
  };
}
```

```ts
// pi-extension/src/index.ts
const extension: ExtensionFactory = createRemotePiExtensionFactory(createLegacyIndexPorts);
export default extension;
```

**Implementation Notes**:
- The epoch is the composition root’s owner token. Any async callback that starts before `session_shutdown` and resumes after shutdown must check `epoch.isCurrent()` before mutating relay, mesh, owner, or session state.
- This step should introduce the shell and delegate to existing callbacks; it should not extract relay/owner/session implementations yet.
- Preserve Pi SDK hook registration order unless a test proves order is irrelevant.

**Acceptance Criteria**:
- [ ] A composition-root module exists and owns `register()` / `dispose()` / epoch creation.
- [ ] `index.ts` default export remains an `ExtensionFactory`.
- [ ] Existing extension registration tests still pass.
- [ ] A new test or targeted assertion verifies `session_shutdown` disposal marks the epoch before late async continuations can publish state.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

**Rollback**: Revert the new composition-root module and restore the inline `const extension: ExtensionFactory = ...` body in `index.ts`.

---

### Step 3: Build legacy adapters for the four future modules
**Priority**: High
**Risk**: High
**Source Lens**: missing abstraction / pattern drift
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/legacy_ports.ts`, `pi-extension/src/extension/ports.ts`
**Story**: `epic-bold-split-pi-extension-index-composition-root-step-3`

**Current State**:
```ts
// Cross-cutting helpers are free functions over shared globals.
function _broadcastToActive(msg: ServerMessage): void { /* _activePeers */ }
function _publishWorking(working: boolean): void { /* _myRoomMeta + _relay */ }
function _attachBridgeIfReady(): void { /* _meshNode + _relay + _cachedEd25519 */ }
function _routeClientMessageFrom(sender: PlainPeerChannel, msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void { /* everything */ }
```

**Target State**:
```ts
// pi-extension/src/extension/legacy_ports.ts
import type { RemotePiRuntimePorts } from "./ports.js";

export function createLegacyIndexPorts(deps: LegacyIndexDeps): RemotePiRuntimePorts {
  return {
    relay: createLegacyRelayTransport(deps),
    owners: createLegacyOwnerMultiplexer(deps),
    session: createLegacySdkSessionProjection(deps),
    commands: createLegacyCommandSurface(deps),
  };
}
```

```ts
// pi-extension/src/index.ts
function createIndexDeps(): LegacyIndexDeps {
  return {
    relay: () => _relay,
    setRelay: (relay) => { _relay = relay; },
    activePeers: _activePeers,
    broadcastToActive: _broadcastToActive,
    routeClientMessageFrom: _routeClientMessageFrom,
    publishWorking: _publishWorking,
    cmdRoot: _cmdRoot,
    cmdStart: _cmdStart,
    cmdStop: _cmdStop,
    cmdPair: _cmdPair,
    // ...callbacks grouped by owning future module...
  };
}

function createLegacyIndexPorts(): RemotePiRuntimePorts {
  return createLegacyIndexPortsFromDeps(createIndexDeps());
}
```

**Implementation Notes**:
- This step is allowed to add adapter objects that wrap existing functions. Do not move large function bodies yet.
- Keep the dependency object grouped by future module ownership so later sibling features can replace one adapter at a time.
- Do not let `legacy_ports.ts` reach into module globals directly. It receives callbacks/state accessors from `index.ts`, which makes the future extraction seam explicit.
- Use `unknown` + narrowing at inbound JSON boundaries exactly as today; no validation semantics change.

**Acceptance Criteria**:
- [ ] Four legacy adapters satisfy `RemotePiRuntimePorts`.
- [ ] The adapter dependency object is the only place where the composition root knows today’s god-file globals.
- [ ] No app/client wire behavior changes; pairing, reconnect, session sync, and commands still route through existing implementations.
- [ ] `corepack pnpm typecheck` passes.

**Rollback**: Inline the adapter object back into `index.ts` and remove `legacy_ports.ts`; because this is wrapper-only, rollback should not touch protocol or module internals.

---

### Step 4: Route hooks, commands, and app ingress through the ports
**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle ownership
**Files**: `pi-extension/src/extension/composition_root.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-composition-root-step-4`

**Current State**:
```ts
pi.on("session_start", (_event, ctx) => {
  _lastEventCtx = ctx;
  if (_disposed) {
    _disposed = false;
    void _cmdRoot(ctx);
  }
});

pi.on("session_shutdown", async () => {
  _disposed = true;
  _lastCtx = null;
  _lastEventCtx = null;
  _messageApi = null;
  _pi = null;
  if (_meshNode) await _meshNode.close();
  if (_state !== "idle") _goIdle();
});

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
// pi-extension/src/extension/composition_root.ts
function registerLifecycleHooks(pi: ExtensionAPI, ports: RemotePiRuntimePorts, epoch: RuntimeEpoch): void {
  pi.on("session_start", (_event, ctx) => {
    ports.session.bindSessionContext(ctx);
    if (!epoch.isCurrent()) return;
    ports.commands.ensureStarted?.(ctx);
  });

  pi.on("session_shutdown", async () => {
    epoch.dispose();
    ports.session.clearStaleContexts();
    ports.relay.detachCrossPcBridge();
    ports.relay.stop();
    await ports.commands.closeMesh?.();
  });
}

function registerOwnerIngress(ports: RemotePiRuntimePorts): void {
  ports.relay.onOuterMessage((line) => {
    // Decode/known-peer/pair routing stays in the owner/relay adapters.
    // Once attached, app messages enter only through owners.routeFrom(...).
  });
}
```

**Implementation Notes**:
- Keep `PlainPeerChannel` and relay listener behavior unchanged; only change which named port owns the callback.
- Explicitly preserve the stale-context fix: session actions use the freshest session-start/withSession context, never the pre-replacement command context when a fresh one exists.
- Explicitly preserve the late-attach safety requirement: after awaits in relay connect, mesh join, bridge attach, and session replacement callbacks, check the epoch/disposed state before installing listeners or publishing state.
- If a direct route would require changing public behavior, stop that sub-change and leave it to a non-refactor story.

**Acceptance Criteria**:
- [ ] Pi hook registration flows through `composition_root.ts`.
- [ ] Command registration flows through `CommandSurfacePort`.
- [ ] Owner/app inbound messages flow through `OwnerMultiplexerPort.routeFrom` / `SdkSessionProjectionPort.handleClientMessage` instead of free-floating calls from multiple modules.
- [ ] Tests cover stale context after app-triggered `session_new` and late relay/bridge teardown guards.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

**Rollback**: Restore direct hook/command registration in `index.ts` and keep the port definitions unused; behavior should return to the pre-step route graph.

---

### Step 5: Lock compatibility seams and test-harness exports
**Priority**: Medium
**Risk**: Medium
**Source Lens**: pattern drift / dead weight prevention
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/testing.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/e2e.test.ts`
**Story**: `epic-bold-split-pi-extension-index-composition-root-step-5`

**Current State**:
```ts
// Tests import many private helpers directly from index.ts.
export async function _connectForTest(ctx: unknown): Promise<void> { /* ... */ }
export function _getState(): "idle" | "started" | "paired" { /* ... */ }
export function routeClientMessage(msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void { /* ... */ }
export async function probeListPeers(sockPath: string, timeoutMs = 2000): Promise<string[] | null> { /* ... */ }
```

**Target State**:
```ts
// pi-extension/src/extension/testing.ts
export interface RemotePiTestHarness {
  connect(ctx: unknown): Promise<void>;
  stop(ctx: unknown): Promise<void>;
  state(): "idle" | "started" | "paired";
  routeClientMessage(message: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void;
}

// pi-extension/src/index.ts
export { probeListPeers } from "./extension/probe_list_peers.js";
export const _connectForTest = legacyHarness.connect;
export const _stopForTest = legacyHarness.stop;
export const _getState = legacyHarness.state;
export const routeClientMessage = legacyHarness.routeClientMessage;
```

**Implementation Notes**:
- This is compatibility hardening, not cleanup for its own sake. Keep existing test imports working while adding a named harness surface for future module tests.
- Do not delete legacy `_fooForTest` exports in this feature; deprecating them can be a later cleanup after sibling modules land.
- Move only pure helpers such as `probeListPeers` if doing so is behavior-preserving and test coverage stays green.

**Acceptance Criteria**:
- [ ] Existing tests import and pass without mass rewrites.
- [ ] New or updated tests can instantiate the composition root through a harness rather than patching module globals directly.
- [ ] Public package exports remain unchanged except for additive internal test exports.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass.

**Rollback**: Remove the new harness wrapper and restore direct `_fooForTest` functions in `index.ts`.

## Implementation Order
1. `epic-bold-split-pi-extension-index-composition-root-step-1` — define the type-level port registry.
2. `epic-bold-split-pi-extension-index-composition-root-step-2` — add the composition-root shell and lifecycle epoch.
3. `epic-bold-split-pi-extension-index-composition-root-step-3` — build legacy adapters for relay, owners, SDK session projection, and commands.
4. `epic-bold-split-pi-extension-index-composition-root-step-4` — route hooks/commands/app ingress through the ports.
5. `epic-bold-split-pi-extension-index-composition-root-step-5` — lock compatibility seams and test-harness exports.

## Composition-root and port boundaries
- **Composition root**: `extension/composition_root.ts`; owns Pi SDK registration order, runtime epoch/disposal, and wiring. It must not own relay sockets, owner maps, session buffers, pairing storage, or daemon registry state.
- **RelayTransportPort**: owns relay URL resolution at transport start, `RelayClient`, reconnect/backoff, relay state event emission, room-meta sends, and cross-PC bridge attachment/detachment. It must expose epoch-safe async continuation points for reconnect and bridge attach.
- **OwnerMultiplexerPort**: owns app owner channels, `_activePeers` replacement, per-owner attach/detach, broadcast fanout, late-attach sync targets, and known-peer/pair ingress handoff.
- **SdkSessionProjectionPort**: owns Pi SDK session context freshness, `_messageApi`/fresh action API binding, `_messageBuffer`, `_sessionStartedAt`, current turn/queued-message projection, working-state publication requests, and app action dispatch into `actions/handlers.ts`.
- **CommandSurfacePort**: owns `/remote-pi` command registration, daemon/cron/service commands, setup wizard, standalone CLI compatibility, and invocation of relay/owner/session ports. It may depend on ports; ports must not depend on command registration.

## Risk and rollback summary
- Highest risk is lifecycle ordering around `session_shutdown`, `ctx.newSession({ withSession })`, relay reconnect, and `MeshNode.attachBridge()` late continuations. Every async boundary introduced by the composition root carries an epoch/disposed check.
- Rollback is step-local because steps first add types, then a root shell, then wrappers, then route traffic. If a routed step fails, revert only that step and keep prior type definitions if harmless.
- Observable behavior must remain unchanged: same CLI commands, same app wire messages, same relay room derivation, same pairing semantics, same test-only compatibility exports unless an export is replaced by an alias.

## Convention-driven steps
No project-specific `.agents/skills/refactor-conventions/` catalog exists. The plan uses the default refactor-design lenses plus repo rules: ports/adapters, single source of truth, fail-fast boundaries, lifecycle ownership, and test integrity.

## Atomic steps acknowledged
No step intentionally changes public protocol or CLI API. Step 4 is the only semi-atomic route change because hook/command/app ingress must agree on the same runtime epoch. It remains rollbackable as one commit by restoring direct `index.ts` registration and callbacks.
