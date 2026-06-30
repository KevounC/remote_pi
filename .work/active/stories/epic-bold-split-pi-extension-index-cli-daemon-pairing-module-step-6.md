---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-6
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
depends_on: [epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-5]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation
- Extracted standalone CLI dispatch to `pi-extension/src/extension/command_surface/standalone_cli.ts` as `runStandaloneRemotePiCli(...)`, with injected handlers for devices/revoke/set-relay/create/remove/daemons/daemon/cron/peers/claude/install/uninstall/restart-supervisor.
- Kept `pi-extension/src/index.ts` as the CLI bootstrap/wiring point: it preserves the shebang, keeps `package.json` bin unchanged (`remote-pi: dist/index.js`), checks `isDirectRun(import.meta.url, process.argv[1])`, and passes the existing command handler instances into `createStandaloneCliDeps(...)`.
- Added the compatibility command-surface harness in `pi-extension/src/extension/testing.ts`; legacy test exports from `index.ts` remain available, and `index.ts` also exports `commandSurfaceHarness` for newer tests/seams.
- Moved the `remote-pi claude` launcher body into the standalone CLI module while passing the package entrypoint URL from `index.ts`, preserving the built `dist/index.js` path assumptions for `dist/mcp/mesh_server.js` and packaged `skills/agent-network/SKILL.md`.
- Updated `src/session/e2e.test.ts` to import `probeListPeers` from its extracted module instead of from `index.ts`.
- Added CLI dispatcher coverage in `src/extension.test.ts` for the published standalone paths and argument re-quoting.
- Verification: `corepack pnpm typecheck` clean; `corepack pnpm build` clean; `corepack pnpm exec vitest run src/extension.test.ts -t "standalone|cli|devices|revoke|set-relay|create|daemon|cron|peers|install|supervisor"` passed 31 tests / 118 skipped in 1 file.
- `corepack pnpm exec vitest run src/session/e2e.test.ts` reported 4 passed / 28 failed; every failure hit leader-election/UDS broker setup (`leader election failed after 20 attempts: /tmp/pi-e2e-*/broker.sock`) before behavior assertions, matching the known mesh/UDS false-alarm group called out for this wave. No code changes were made to chase that environment failure.
- Discrepancies from design: `index.ts` necessarily remains the broader legacy composition root for owner/session/transcript wiring outside this CLI/daemon/pairing arc, but the standalone CLI dispatcher and `remote-pi claude` command body are no longer embedded there.
- Adjacent issues parked: none.

## Rollback
Restore the direct-run `if (_isDirectRun())` block and compatibility helpers to `index.ts`. If a wrapper file/package bin change was made, revert it with this step.

## Review

Approved (2026-06-30) with HIGH-risk CLI-bootstrap verification. Independently
re-ran: `corepack pnpm typecheck` clean; `corepack pnpm build` clean; `vitest run
src/extension.test.ts -t "standalone|cli|devices|revoke|set-relay|create|daemon|
cron|peers|install|supervisor"` → 31/31; **full pi-ext suite 649 passed | 3 skipped
| 0 failed (44 files)** — fully green (up from 648 — the agent's new CLI tests).

NOTE: the implementer CORRECTLY identified the false-failure pattern (4th
consecutive pi-ext agent to do so) — reported e2e.test.ts "28 failed... matching
the known mesh/UDS false-alarm group. I did not chase it." The orchestrator's
independent vitest run confirms 0 failures.

Commit `defbd09` scoped to pi-ext only (standalone_cli.ts new 296 lines + testing.ts
harness + index.ts shrunk ~300 lines + tests + story .md); collision guard held.
CLI bootstrap verified: `runStandaloneRemotePiCli` + `isDirectRun` +
`createStandaloneCliDeps` extracted to standalone_cli.ts; `index.ts` bootstraps
direct-run CLI through it (shebang `#!/usr/bin/env node` preserved; package.json
bin remains `dist/index.js`); `RemotePiCommandSurfaceHarness` compat harness in
testing.ts (legacy test exports remain available); all CLI paths execute
(devices/revoke/set-relay/create/remove/daemons/daemon/cron/peers/claude/install/
uninstall/restart-supervisor). **cli-daemon-pairing arc complete (6/6).**
