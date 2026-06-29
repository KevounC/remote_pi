---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-6
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
depends_on: [epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-5]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 6: Extract the standalone CLI dispatcher and compatibility harness; finish `index.ts` as wiring

**Priority**: Medium  
**Risk**: High  
**Source Lens**: code smell / test seam hardening  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/standalone_cli.ts`, `pi-extension/src/extension/testing.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/package.json`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/e2e.test.ts`

## Current State
```ts
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

export async function _connectForTest(ctx: unknown): Promise<void> { /* ... */ }
export function _getState(): "idle" | "started" | "paired" { /* ... */ }
export function routeClientMessage(msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void { /* ... */ }
```

## Target State
```ts
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

const extension: ExtensionFactory = createRemotePiExtensionFactory(createLegacyIndexPorts);
export default extension;

if (isDirectRun(import.meta.url, process.argv[1])) {
  await runStandaloneRemotePiCli(process.argv, createStandaloneCliDeps(commandSurfaceHarness));
}
```

```ts
export interface RemotePiCommandSurfaceHarness {
  connect(ctx: unknown): Promise<void>;
  stop(ctx: unknown): Promise<void>;
  state(): "idle" | "started" | "paired";
  handleControl(cmd: string): Promise<void>;
  resetCwdLock(): void;
  restartSupervisorCommand(platform: NodeJS.Platform, uid: number): RestartStep[] | null;
}
```

## Implementation Notes
- Keep `package.json` bin unchanged (`remote-pi: dist/index.js`) unless a tiny wrapper file is unavoidable. If a wrapper is added, make `dist/index.js` continue to work for both Pi extension loading and CLI execution.
- Preserve shebang behavior for the published `remote-pi` binary.
- Keep legacy test exports from `index.ts` as aliases during the split so sibling module implementations can land without a mass test rewrite. New tests should prefer `extension/testing.ts`.
- The final `index.ts` should contain only imports, legacy port construction, default extension export, direct-run CLI bootstrap, and compatibility exports. Large command bodies should be gone.

## Acceptance Criteria
- [ ] Standalone `remote-pi` CLI dispatch lives outside `index.ts` and preserves help text and subcommand behavior.
- [ ] `index.ts` is a thin wiring file for command surface plus other composition-root ports.
- [ ] Existing test-only exports remain available or are explicitly aliased from `extension/testing.ts`.
- [ ] `remote-pi devices/revoke/set-relay/create/remove/daemons/daemon/cron/peers/claude/install/uninstall/restart-supervisor` CLI paths still execute through the same command handlers.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass.

## Rollback
Restore the direct-run `if (_isDirectRun())` block and compatibility helpers to `index.ts`. If a wrapper file/package bin change was made, revert it with this step.
