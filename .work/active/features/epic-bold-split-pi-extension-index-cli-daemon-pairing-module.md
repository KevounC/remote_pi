---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
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

# Split pi-extension index — CLI / daemon / pairing module

## Brief
CLI/command (`remote-pi` command + `if/else` router at `index.ts:1635-1688`),
daemon/cron, and pairing extracted from `index.ts` as a named module. Globals
`_pi`, `_stopAutoListener`, `_cachedEd25519`, `_selfRevoke`, `_cwdLock`,
`_lockedName` (`index.ts:547-585`) become this module's private state. The
pairing path stays paired with the owner-multiplexer module's peer attachment.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:547-585`, `:1635-1688`;
  `pi-extension/src/daemon/`, `pi-extension/src/pairing/`.

<!-- /agile-workflow:refactor-design pins the module boundary. -->

## Design decisions
- Autopilot judgment mode: treat this as a pure structure-preserving refactor. `/remote-pi` command names, command descriptions, command output strings, standalone `remote-pi` CLI output, daemon supervisor integration, QR URI shape, pairing replies, and app wire semantics must remain byte-for-byte compatible unless an existing test proves the old text was already unstable.
- Sibling dependency: step 1 explicitly depends on `epic-bold-split-pi-extension-index-composition-root` because this module implements the `CommandSurfacePort` introduced there. The chain is linear after step 1.
- Dispatch rationale: direct-read design in this delegated sub-agent. The target was bounded to one god-file slice plus already-named `daemon/`, `pairing/`, and wizard modules; no exploratory fan-out was used. This avoids adding same-context summary drift to a mechanical extraction plan. If implementation fans out, use openai-codex workers per the parent autopilot instruction.
- Work-view note: `.work/bin/work-view` is absent in this checkout, so dependency safety was checked by a manual frontmatter DFS over existing active items plus the proposed six-story chain. Result: no cycle.
- Boundary split with owner-multiplexer: this feature owns QR issuance, peer persistence, pair-request validation/reply, command registration, daemon/cron/service command handlers, setup wizard invocation, standalone CLI parsing, `_cwdLock`/`_lockedName`, `_cachedEd25519`, `_selfRevoke`, and the relay auto-listener lifetime. It does not own owner channel fanout. Pairing completion calls the owner-multiplexer through `OwnerMultiplexerPort.attach(...)` / `routeFrom(...)` so the later owner-multiplexer module can replace `_activePeers` without revisiting command code.
- Boundary split with SDK-session projection: this feature may keep a private `_pi` binding only for command registration, thinking-level reads during relay start, and transparent RPC/control command entry. Agent message sending, fresh session context, and session action dispatch stay behind `SdkSessionProjectionPort` once composition-root ports are available. Do not create a second message/session authority in the command module.
- Patchbay migration guard: exported interfaces and file names should be host-neutral (`CommandSurface`, `CommandSurfaceDeps`, `DaemonCommandHandlers`, `PairingCoordinator`) rather than hard-coding assumptions that only the current Pi extension can satisfy. Patchbay should be able to reuse command/pairing/daemon orchestration while swapping the host/runtime adapters.

## Refactor Overview
`pi-extension/src/index.ts` currently registers the extension, owns all `/remote-pi` slash command surfaces, embeds a duplicate command router and nested command registrations, starts/stops relay and local mesh state, generates QR pairing codes, validates pair requests, calls the daemon supervisor, owns cron command parsing, installs/uninstalls the supervisor service, and doubles as the standalone `remote-pi` CLI. The surrounding modules already exist (`daemon/`, `pairing/`, `session/setup_wizard.ts`), but `index.ts` still coordinates them through module globals and free functions.

The target is a named command-surface module implementing the composition-root `CommandSurfacePort`. `index.ts` becomes wiring: it creates legacy adapters for relay/owner/session ports and installs `createCommandSurface(...)`. Command behavior stays preserved while ownership moves behind explicit dependencies. The owner-multiplexer module remains the long-term owner of attached app channels; this module only creates/validates the pairing flow and asks the owner port to attach or route.

## Refactor Steps

### Step 1: Create the CommandSurface module shell and legacy dependency seam
**Priority**: High
**Risk**: Medium
**Source Lens**: code smell / missing abstraction
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/src/extension/command_surface/legacy_deps.ts`, `pi-extension/src/extension/ports.ts`
**Story**: `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-1`

**Current State**:
```ts
// pi-extension/src/index.ts
const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  _pi = pi;
  _messageApi = pi;
  _refreshPairingsCache();
  pi.on("resources_discover", () => ({ skillPaths: [skillsDir()] }));
  registerAgentTools(pi, () => _meshNode?.peer() ?? null);
  // ...Pi SDK hooks...
  pi.registerCommand("remote-pi", { /* command router */ });
  // ...nested command registrations...
  if (process.env["REMOTE_PI_DAEMON"] === "1") {
    setTimeout(() => { void _cmdRoot(daemonCtx); }, 0);
  }
};
```

**Target State**:
```ts
// pi-extension/src/extension/command_surface.ts
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { CommandSurfacePort, RemotePiRuntime } from "./ports.js";

export interface CommandSurfaceDeps {
  readonly registerAgentTools: (pi: ExtensionAPI) => void;
  readonly deployAgentNetworkSkill: () => void;
  readonly refreshPairingsCache: () => void;
  readonly registerCommands: (pi: ExtensionAPI) => void;
  readonly startDaemonMode: () => void;
}

export function createCommandSurface(deps: CommandSurfaceDeps): CommandSurfacePort {
  return {
    register(pi: ExtensionAPI, _runtime: RemotePiRuntime): void {
      deps.deployAgentNetworkSkill();
      deps.refreshPairingsCache();
      deps.registerAgentTools(pi);
      deps.registerCommands(pi);
      if (process.env["REMOTE_PI_DAEMON"] === "1") deps.startDaemonMode();
    },
  };
}
```

```ts
// pi-extension/src/index.ts
function createLegacyCommandSurface(): CommandSurfacePort {
  return createCommandSurface({
    deployAgentNetworkSkill: _deployAgentNetworkSkill,
    refreshPairingsCache: _refreshPairingsCache,
    registerAgentTools: (pi) => registerAgentTools(pi, () => _meshNode?.peer() ?? null),
    registerCommands: (pi) => _registerRemotePiCommands(pi),
    startDaemonMode: () => _startDaemonMode(),
  });
}
```

**Implementation Notes**:
- This step introduces the behavior-preserving shell only. It may move the command-registration block behind `_registerRemotePiCommands(pi)` but should not move command bodies yet.
- Keep the `CommandSurfacePort` signature from the composition-root feature. If its exact shape differs when implemented, adapt this step to that landed interface instead of inventing a competing port.
- Keep the module side-effect free; the `register(...)` method is the side-effect boundary.
- Preserve the daemon-mode delayed `_cmdRoot` behavior and headless UI filtering exactly.

**Acceptance Criteria**:
- [ ] A named command-surface module exists and satisfies `CommandSurfacePort`.
- [ ] `index.ts` delegates command-surface registration through `createLegacyCommandSurface()` / composition-root ports.
- [ ] `/remote-pi` and nested command registration count/names are unchanged.
- [ ] Daemon auto-init still runs only when `REMOTE_PI_DAEMON=1`.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

**Rollback**: Inline `createCommandSurface(...).register(...)` back into the extension factory and delete the new command-surface shell. Because this step wraps existing calls only, rollback does not touch protocol, daemon, or pairing internals.

---

### Step 2: Replace duplicated slash-command registration with one command registry
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / single source of truth
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/commands.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-2`

**Current State**:
```ts
pi.registerCommand("remote-pi", {
  getArgumentCompletions: async (prefix) => {
    return [
      "setup", "status", "stop", "pair", "devices", "revoke", "set-relay",
      "peers", "create", "remove", "daemons",
      "daemon start", "daemon stop", "daemon restart", "daemon send", "daemon status",
      "cron", "cron add", "cron list", "cron remove", "cron enable", "cron disable", "cron run", "cron log",
      "install", "uninstall",
    ].filter((o) => o.startsWith(prefix)).map((o) => ({ value: o, label: o }));
  },
  handler: async (args, ctx) => {
    const sub = args.trim();
    if      (sub === "")                       { await _cmdRoot(ctx); }
    else if (sub === "setup")                  { await _cmdSetup(ctx); }
    else if (sub === "status")                 { _cmdStatus(ctx); }
    // ...long if/else router...
    else                                       { await _cmdRoot(ctx); }
  },
});

pi.registerCommand("remote-pi setup", { description: "Run the setup wizard and update local config", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdSetup(ctx); } });
// ...19 more nested registrations...
```

**Target State**:
```ts
// pi-extension/src/extension/command_surface/commands.ts
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";

export interface RemotePiCommandSpec {
  readonly suffix: string;
  readonly description: string;
  readonly completionValues?: readonly string[];
  readonly complete?: (prefix: string) => Promise<Array<{ value: string; label: string }>>;
  readonly run: (args: string, ctx: ExtensionCommandContext) => void | Promise<void>;
}

export function registerRemotePiCommands(pi: ExtensionAPI, specs: readonly RemotePiCommandSpec[]): void {
  const rootCompletions = rootCompletionValues(specs);
  pi.registerCommand("remote-pi", {
    description: "Connect (join local mesh + start relay), or run setup on first use",
    getArgumentCompletions: async (prefix) => completeRoot(prefix, rootCompletions, specs),
    handler: async (args, ctx) => dispatchRoot(specs, args.trim(), ctx),
  });
  for (const spec of specs) {
    pi.registerCommand(`remote-pi ${spec.suffix}`, {
      description: spec.description,
      ...(spec.complete ? { getArgumentCompletions: spec.complete } : {}),
      handler: async (args, ctx) => spec.run(args.trim(), ctx),
    });
  }
}
```

```ts
// command specs preserve existing names/descriptions/handlers.
const COMMAND_SPECS = [
  { suffix: "setup", description: "Run the setup wizard and update local config", run: (_args, ctx) => this.setup(ctx) },
  { suffix: "status", description: "Show local mesh + relay status", run: (_args, ctx) => this.status(ctx) },
  { suffix: "stop", description: "Stop everything (leave local mesh + disconnect relay)", run: (_args, ctx) => this.stop(ctx) },
  // ...same public command set as today...
] as const;
```

**Implementation Notes**:
- Preserve the public command set exactly: `remote-pi`, `setup`, `status`, `stop`, `pair`, `devices`, `revoke`, `set-relay`, `peers`, `create`, `remove`, `daemons`, daemon subcommands, `cron`, `install`, `uninstall`.
- Preserve removed-command behavior: names intentionally absent in `extension.test.ts` (`join`, `leave`, `relay start`, `config`, etc.) must stay absent.
- Preserve root-router fallback: unknown or empty root subcommands still call the root connect path.
- Keep root completions for prefix strings like `revoke ` by delegating to the same short-id completion callback.

**Acceptance Criteria**:
- [ ] Root command completions and nested registrations derive from one registry/spec table.
- [ ] The command registration test still sees exactly the same command names/count.
- [ ] Command descriptions remain unchanged for user-facing commands.
- [ ] Unknown root subcommands still fall back to the root command path.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

**Rollback**: Restore the explicit `pi.registerCommand(...)` block and delete the registry helper. Command bodies remain untouched by this step.

---

### Step 3: Move setup, local-mesh command lifecycle, and RPC control into CommandSurface
**Priority**: High
**Risk**: High
**Source Lens**: lifecycle ownership / code smell
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/src/extension/command_surface/local_mesh_commands.ts`, `pi-extension/src/extension/command_surface/control_commands.ts`, `pi-extension/src/extension/probe_list_peers.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/e2e.test.ts`
**Story**: `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-3`

**Current State**:
```ts
// pi-extension/src/index.ts
let _pi: ExtensionAPI | null = null;
let _cwdLock: AcquiredLock | null = null;
let _lockedName: string | null = null;
let _lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;

async function _cmdRoot(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* cwd lock, setup wizard, join, relay start */ }
async function _cmdSetup(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* runSetupWizard */ }
async function _cmdJoin(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* MeshNode, agent-network skill, bridge attach */ }
async function _cmdStop(ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* mesh close + _goIdle */ }
export async function _handleControl(cmd: string): Promise<void> { /* relay:on/off/toggle/status, rename */ }
export async function probeListPeers(sockPath: string, timeoutMs = 2000): Promise<string[] | null> { /* UDS observer probe */ }
```

**Target State**:
```ts
// pi-extension/src/extension/command_surface/local_mesh_commands.ts
export interface LocalMeshCommandDeps {
  readonly relay: RelayControl;
  readonly session: SdkSessionProjectionPort;
  readonly makeMeshNode: (input: { sockPath: string; name: string; cwd: string; auditPath: string }) => MeshNode;
  readonly attachBridgeIfReady: () => void;
  readonly refreshFooter: () => void;
  readonly emitRelayState: (force?: boolean) => void;
}

export class LocalMeshCommands {
  private cwdLock: AcquiredLock | null = null;
  private lockedName: string | null = null;
  private lastCtx: Pick<ExtensionContext, "ui" | "abort" | "cwd"> | null = null;

  async root(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* existing _cmdRoot body */ }
  async setup(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* existing _cmdSetup body */ }
  async join(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* existing _cmdJoin body */ }
  async stop(ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* existing _cmdStop body */ }
  async handleControl(cmd: string): Promise<void> { /* existing _handleControl body */ }
  resetCwdLockForTest(): void { /* existing test helper behavior */ }
}
```

```ts
// pi-extension/src/extension/probe_list_peers.ts
export async function probeListPeers(sockPath: string, timeoutMs = 2000): Promise<string[] | null> {
  // existing pure UDS observer probe body
}

// pi-extension/src/index.ts
export { probeListPeers } from "./extension/probe_list_peers.js";
export const _handleControl = commandSurfaceHarness.handleControl;
export const _resetCwdLockForTest = commandSurfaceHarness.resetCwdLock;
```

**Implementation Notes**:
- Move `_cwdLock` and `_lockedName` into the command-surface/local-mesh class in this step. Keep compatibility test exports as aliases until the whole split lands.
- Preserve all race guards that check `_disposed` after `_cmdJoin`/`_cmdStart` awaits. If composition-root exposes a runtime epoch, depend on that rather than a raw boolean.
- Keep `MeshNode` ownership clear: the command surface may own starting/stopping the local mesh because `/remote-pi` and daemon mode invoke it, but cross-PC bridge attachment should remain delegated through the relay/owner/session ports as they land.
- Extract `probeListPeers` because standalone CLI and `session/e2e.test.ts` already depend on it as a pure utility; this reduces direct `index.ts` test imports without changing public package behavior.

**Acceptance Criteria**:
- [ ] `_cwdLock` and `_lockedName` are private fields of the command-surface/local-mesh controller.
- [ ] `/remote-pi`, `/remote-pi setup`, `/remote-pi stop`, `/remote-pi peers`, control `relay:*`, and control `rename:*` preserve current notifications and state transitions.
- [ ] `probeListPeers` lives outside `index.ts` and is re-exported compatibly.
- [ ] Existing stale/shutdown race tests around `_cmdJoin`, `_cmdStart`, `session_shutdown`, `CTRL_PREFIX`, and rename still pass.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts src/session/e2e.test.ts` pass.

**Rollback**: Move the local-mesh/control bodies and test aliases back to `index.ts`; because state fields move together, rollback is a file-level revert for the new local-mesh command files.

---

### Step 4: Move relay-facing command handlers and QR pairing coordinator behind owner/session ports
**Priority**: High
**Risk**: High
**Source Lens**: missing abstraction / lifecycle ownership
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/pairing_commands.ts`, `pi-extension/src/extension/command_surface/pairing_coordinator.ts`, `pi-extension/src/extension/command_surface/relay_commands.ts`, `pi-extension/src/pairing/qr.ts`, `pi-extension/src/pairing/storage.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-4`

**Current State**:
```ts
// pi-extension/src/index.ts
let _stopAutoListener: (() => void) | null = null;
let _cachedEd25519: Ed25519Keypair | null = null;
let _selfRevoke: SelfRevoke | null = null;

async function _cmdStart(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* keyring, room_meta, RelayClient.connect, SelfRevoke, bridge attach */ }
async function _cmdPair(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> { /* issue QR token + send pair-code */ }
async function _cmdList(ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* listPeers */ }
async function _cmdRevoke(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* removePeer + detach channel */ }
function _installAutoListener(relay: RelayClient): () => void { /* outer decode, pair_request, known-peer reconnect */ }
async function _handlePairRequest(relay: RelayClient, appPeerId: string, inner: PairRequest): Promise<void> { /* token, addPeer, pair_ok */ }
```

**Target State**:
```ts
// pi-extension/src/extension/command_surface/pairing_coordinator.ts
export interface PairingCoordinatorDeps {
  readonly owners: OwnerMultiplexerPort;
  readonly session: SdkSessionProjectionPort;
  readonly relay: RelayTransportPort;
  readonly sendPiMessage: (message: Parameters<ExtensionAPI["sendMessage"]>[0], label: string) => boolean;
  readonly currentCwd: () => string;
  readonly displayName: (cwd: string) => string;
  readonly currentRoomId: () => string | null;
  readonly currentSessionStartedAt: () => number | null;
  readonly currentSessionId: () => string;
}

export class PairingCoordinator {
  private cachedEd25519: Ed25519Keypair | null = null;
  private stopAutoListener: (() => void) | null = null;
  private selfRevoke: SelfRevoke | null = null;

  async startRelay(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* existing _cmdStart behavior */ }
  async showPairQr(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> { /* existing _cmdPair behavior */ }
  async listDevices(ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* existing _cmdList behavior */ }
  async revokeDevice(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* existing _cmdRevoke behavior */ }
  installAutoListener(relay: RelayClient): () => void { /* existing listener, but calls this.handlePairRequest(...) */ }
  async handlePairRequest(relay: RelayClient, appPeerId: string, inner: PairRequest): Promise<void> { /* token + addPeer + pair_ok */ }
}
```

```ts
// Pairing completion delegates channel ownership.
const channel = deps.owners.attach({
  relay,
  appPeerId,
  peerName: inner.device_name,
  roomId: deps.currentRoomId() ?? roomIdFor(cwd, sessionName),
  routeMessage: (sender, msg) => deps.session.handleClientMessage(sender, msg),
});
```

**Implementation Notes**:
- Move `_cachedEd25519`, `_stopAutoListener`, and `_selfRevoke` into the pairing/relay command coordinator in this step.
- Preserve keyring behavior exactly: transient keyring failures still surface the current user-facing warning and must not generate a new identity on macOS/Windows.
- Preserve room identity invariants: room id derives from `(cwd, displayName)`, QR `rm` matches the relay hello room, and `pair_ok.room_id` uses the same fallback.
- Preserve auto-listener semantics: already-attached owners are ignored by the listener; known peers reconnect without a QR; unknown non-pair messages receive `unknown_peer`; `pair_request` token errors return the same `pair_error` codes/messages.
- Pairing may call `OwnerMultiplexerPort.attach(...)`, but it must not mutate `_activePeers` directly after this step.
- Keep `SelfRevoke` callback behavior: revoke only the matching owner, refresh pairings cache/footer, emit `remote-pi:mesh-revoked`, and update `MeshNode` siblings through the appropriate mesh/owner bridge dependency.

**Acceptance Criteria**:
- [ ] `_cachedEd25519`, `_stopAutoListener`, and `_selfRevoke` no longer live in `index.ts`.
- [ ] `/remote-pi pair`, `/remote-pi devices`, `/remote-pi revoke`, `/remote-pi set-relay`, relay start/reconnect, and QR copy-paste payloads preserve behavior.
- [ ] Pair request success/error/reconnect tests still pass, including `pair_ok` fields `session_name`, `session_started_at`, `session_id`, `room_id`, `harness`, and `hostname`.
- [ ] The module delegates owner channel attachment/routing through owner/session ports or legacy owner/session adapters.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts src/pairing/qr.test.ts src/pairing/storage.test.ts` pass.

**Rollback**: Move the relay/pairing command bodies and private state back to `index.ts`, then restore direct `_attachOwner` / `_routeClientMessageFrom` calls. Storage and QR helper modules are not changed by this step, so persisted data rollback is not needed.

---

### Step 5: Move daemon, cron, service-install, and supervisor-restart command handlers out of index
**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / missing abstraction
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/daemon_commands.ts`, `pi-extension/src/extension/command_surface/cron_commands.ts`, `pi-extension/src/extension/command_surface/service_commands.ts`, `pi-extension/src/extension/command_surface/supervisor_restart.ts`, `pi-extension/src/daemon/*.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/daemon/*.test.ts`
**Story**: `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-5`

**Current State**:
```ts
// pi-extension/src/index.ts
async function _cmdCreate(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* addDaemon + callSupervisor start */ }
async function _cmdRemove(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* supervisor unregister fallback */ }
async function _cmdDaemonStart(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> { /* callSupervisor */ }
async function _cmdCron(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* tokenize + cron ops */ }
function _cmdInstall(ctx: Pick<ExtensionContext, "ui">, opts: { linkCli?: boolean } = {}): boolean { /* installService + linkCliBinaries */ }
export function _restartSupervisorCommand(platform: NodeJS.Platform, uid: number): RestartStep[] | null { /* OS command plan */ }
```

**Target State**:
```ts
// pi-extension/src/extension/command_surface/daemon_commands.ts
export class DaemonCommands {
  async create(arg: string, ctx: UiCtx): Promise<void> { /* existing _cmdCreate body */ }
  async remove(arg: string, ctx: UiCtx): Promise<void> { /* existing _cmdRemove body */ }
  async list(ctx: UiCtx): Promise<void> { /* existing _cmdDaemonsList body */ }
  async start(ctx: UiCtx, id?: string): Promise<void> { /* existing _cmdDaemonStart body */ }
  async stop(ctx: UiCtx, id?: string): Promise<void> { /* existing _cmdDaemonStop body */ }
  async restart(ctx: UiCtx, id?: string): Promise<void> { /* existing _cmdDaemonRestart body */ }
  async status(ctx: UiCtx): Promise<void> { /* existing _cmdDaemonStatus body */ }
  async send(arg: string, ctx: UiCtx): Promise<void> { /* existing _cmdDaemonSend body */ }
}

// pi-extension/src/extension/command_surface/cron_commands.ts
export class CronCommands {
  async run(arg: string, ctx: UiCtx): Promise<void> { /* existing _cmdCron dispatcher */ }
}

// pi-extension/src/extension/command_surface/service_commands.ts
export class ServiceCommands {
  install(ctx: UiCtx, opts: { linkCli?: boolean } = {}): boolean { /* existing _cmdInstall body */ }
  uninstall(ctx: UiCtx, opts: { linkCli?: boolean } = {}): void { /* existing _cmdUninstall body */ }
}

// pi-extension/src/extension/command_surface/supervisor_restart.ts
export function restartSupervisorCommand(platform: NodeJS.Platform, uid: number): RestartStep[] | null { /* existing pure body */ }
export function restartSupervisor(): void { /* existing side-effect body */ }
```

**Implementation Notes**:
- Do not move the already-good daemon implementation modules (`daemon/supervisor.ts`, `daemon/registry.ts`, `daemon/cron_registry.ts`, etc.) unless an import cycle requires a small type move. This step moves only command wrappers/parsers out of `index.ts`.
- Preserve exact user-facing messages. Many tests assert substrings and the CLI is operator-facing.
- Keep fallback behavior when supervisor is offline: registry-only list, friendly `SupervisorOfflineError` messages, and registry-only remove fallback.
- Keep Windows-specific spawn/service safeguards intact by importing existing daemon/install helpers rather than rewriting them.

**Acceptance Criteria**:
- [ ] Daemon, cron, service, and supervisor-restart command wrappers no longer live in `index.ts`.
- [ ] `daemon/` modules remain the single source of daemon runtime behavior; command-surface files are thin orchestration adapters.
- [ ] `/remote-pi create/remove/daemons/daemon */cron/install/uninstall` preserve outputs and error handling.
- [ ] `_restartSupervisorCommand` remains exported compatibly (either as an alias or through a testing harness) for existing tests.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test -- src/extension.test.ts src/daemon`, and `corepack pnpm build` pass.

**Rollback**: Move the command wrapper classes back into `index.ts` and restore direct imports from `daemon/`. Because daemon runtime modules are not structurally changed, no supervisor state migration is involved.

---

### Step 6: Extract the standalone CLI dispatcher and compatibility harness; finish `index.ts` as wiring
**Priority**: Medium
**Risk**: High
**Source Lens**: code smell / test seam hardening
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/standalone_cli.ts`, `pi-extension/src/extension/testing.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/package.json`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/e2e.test.ts`
**Story**: `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-6`

**Current State**:
```ts
// pi-extension/src/index.ts
export default extension;

function _isDirectRun(): boolean {
  try { return fileURLToPath(import.meta.url) === realpathSync(process.argv[1] ?? ""); }
  catch { return false; }
}

if (_isDirectRun()) {
  const [, , subcmd, ...cliArgs] = process.argv;
  if (subcmd === "devices" || subcmd === "list") { /* listPeers */ }
  else if (subcmd === "revoke") { /* removePeer */ }
  else if (subcmd === "set-relay") { /* saveConfig */ }
  else if (subcmd === "create") { await _cmdCreate(...); }
  // ...daemon, cron, peers, claude, install, uninstall, restart-supervisor, help...
}

// Tests import many private helpers directly from index.ts.
export async function _connectForTest(ctx: unknown): Promise<void> { /* ... */ }
export function _getState(): "idle" | "started" | "paired" { /* ... */ }
export function routeClientMessage(msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void { /* ... */ }
```

**Target State**:
```ts
// pi-extension/src/extension/command_surface/standalone_cli.ts
export interface StandaloneCliDeps {
  readonly devices: () => Promise<void>;
  readonly revoke: (shortid: string) => Promise<void>;
  readonly setRelay: (url: string) => void;
  readonly daemon: DaemonCommands;
  readonly cron: CronCommands;
  readonly service: ServiceCommands;
  readonly probePeers: () => Promise<void>;
  readonly launchClaude: (args: string[]) => Promise<void>;
  readonly restartSupervisor: () => void;
}

export async function runStandaloneRemotePiCli(argv: readonly string[], deps: StandaloneCliDeps): Promise<void> {
  const [, , subcmd, ...cliArgs] = argv;
  // existing direct-run dispatch and help text, unchanged
}

// pi-extension/src/index.ts
const extension: ExtensionFactory = createRemotePiExtensionFactory(createLegacyIndexPorts);
export default extension;

if (isDirectRun(import.meta.url, process.argv[1])) {
  await runStandaloneRemotePiCli(process.argv, createStandaloneCliDeps(commandSurfaceHarness));
}

// pi-extension/src/extension/testing.ts
export interface RemotePiCommandSurfaceHarness {
  connect(ctx: unknown): Promise<void>;
  stop(ctx: unknown): Promise<void>;
  state(): "idle" | "started" | "paired";
  handleControl(cmd: string): Promise<void>;
  resetCwdLock(): void;
  restartSupervisorCommand(platform: NodeJS.Platform, uid: number): RestartStep[] | null;
}
```

**Implementation Notes**:
- Keep `package.json` bin unchanged (`remote-pi: dist/index.js`) unless a tiny wrapper file is unavoidable. If a wrapper is added, make `dist/index.js` continue to work for both Pi extension loading and CLI execution.
- Preserve the shebang behavior for the published `remote-pi` binary.
- Keep legacy test exports from `index.ts` as aliases during the split so sibling module implementations can land without a mass test rewrite. New tests should prefer `extension/testing.ts`.
- The final `index.ts` should contain only imports, legacy port construction, default extension export, direct-run CLI bootstrap, and compatibility exports. Large command bodies should be gone.

**Acceptance Criteria**:
- [ ] Standalone `remote-pi` CLI dispatch lives outside `index.ts` and preserves help text and subcommand behavior.
- [ ] `index.ts` is a thin wiring file for the command surface plus other composition-root ports.
- [ ] Existing test-only exports remain available or are explicitly aliased from `extension/testing.ts`.
- [ ] `remote-pi devices/revoke/set-relay/create/remove/daemons/daemon/cron/peers/claude/install/uninstall/restart-supervisor` CLI paths still execute through the same command handlers.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass.

**Rollback**: Restore the direct-run `if (_isDirectRun())` block and compatibility helpers to `index.ts`. If a wrapper file/package bin change was made, revert it with this step.

## Implementation Order
1. `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-1` — create the `CommandSurfacePort` implementation shell and legacy dependency seam. Depends on `epic-bold-split-pi-extension-index-composition-root`.
2. `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-2` — replace duplicate slash-command registration/router/completions with a command registry.
3. `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-3` — move setup, local mesh command lifecycle, RPC control, cwd lock state, and `probeListPeers`.
4. `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-4` — move relay-facing command handlers, QR pairing, pair-request validation, and pairing private state behind owner/session ports.
5. `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-5` — move daemon, cron, service-install, and supervisor-restart command wrappers out of `index.ts`.
6. `epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-6` — move standalone CLI dispatch, add compatibility harness, and leave `index.ts` as wiring.

## Module shape
- **Command surface composition**: `extension/command_surface.ts` implements `CommandSurfacePort.register(pi, runtime)`. It owns command registration and daemon-mode auto-init, but receives relay/owner/session behavior through ports or legacy adapters.
- **Command registry**: `extension/command_surface/commands.ts` is the single source for slash-command suffixes, descriptions, completions, and root dispatch.
- **Local mesh command controller**: `extension/command_surface/local_mesh_commands.ts` owns setup wizard invocation, local UDS mesh join/stop, `_cwdLock`, `_lockedName`, mesh name assignment events, and `probeListPeers` delegation.
- **Pairing coordinator**: `extension/command_surface/pairing_coordinator.ts` owns keypair caching, QR token/URI issuance, `pair_request` validation, peer persistence, `pair_ok`/`pair_error` replies, self-revoke poller lifecycle, and relay auto-listener lifetime. It delegates owner channel attach/routing.
- **Daemon command adapters**: `extension/command_surface/{daemon_commands,cron_commands,service_commands,supervisor_restart}.ts` own CLI/slash parsing and user-facing notifications while the existing `daemon/` modules remain the runtime source of truth.
- **Standalone CLI**: `extension/command_surface/standalone_cli.ts` owns `process.argv` dispatch and help text; `index.ts` only invokes it when run as the `remote-pi` binary.
- **Compatibility harness**: `extension/testing.ts` exposes stable test seams so existing `_fooForTest` exports can be aliases during the split instead of forcing unrelated test churn.

## Risk and rollback summary
- Highest risk is lifecycle ordering: daemon-mode delayed `_cmdRoot`, `session_shutdown` while `_cmdJoin`/`_cmdStart` awaits, relay reconnect, self-revoke callbacks, and control `rename` relay cycling. Each moved async boundary must keep the existing disposed/epoch check before publishing state or installing listeners.
- Second-highest risk is command compatibility: root completions, nested command names, standalone CLI help text, and notification strings are user-facing. Preserve them and lean on existing `extension.test.ts` coverage.
- Pairing is security-sensitive. Do not change token TTL, QR URI fields (`t`, `epk`, `n`, `rm`), keyring fallback policy, peer storage format, or `pair_ok`/`pair_error` payloads.
- Rollback is step-local: wrapper shell, command registry, local mesh/control extraction, pairing extraction, daemon wrapper extraction, and standalone CLI extraction can each be reverted independently.

## Convention-driven steps
No project-specific `.agents/skills/refactor-conventions/` catalog exists. The plan uses default refactor-design lenses plus repo rules: ports/adapters, single source of truth for command variants, fail-fast boundary parsing, lifecycle ownership, convergent state, and test integrity.

## Atomic steps acknowledged
Step 2 is semi-atomic because root command dispatch and nested command registration must agree on the same registry to avoid transient command drift. Step 4 is semi-atomic because the relay auto-listener, pair-request validation, and owner attachment need a consistent ownership split; it remains rollbackable by restoring the existing listener and `_handlePairRequest` block in one revert. Step 6 is semi-atomic for package-bin compatibility: direct-run CLI bootstrap and compatibility test aliases should move together.

## Review — advanced to done (2026-06-30)

All 6 child steps `done` (command surface → local-mesh lifecycle → setup/pairing
→ relay-facing handlers/QR coordinator → daemon/cron/service → standalone CLI
dispatcher + harness). The `index.ts` god-file's CLI/daemon/pairing surface is
now extracted into command-surface modules; `index.ts` is thin wiring + bootstrap.
Epic complete.
