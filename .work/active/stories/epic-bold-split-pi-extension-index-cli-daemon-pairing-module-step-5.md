---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
depends_on: [epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Move daemon, cron, service-install, and supervisor-restart command handlers out of index

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: code smell / missing abstraction  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/daemon_commands.ts`, `pi-extension/src/extension/command_surface/cron_commands.ts`, `pi-extension/src/extension/command_surface/service_commands.ts`, `pi-extension/src/extension/command_surface/supervisor_restart.ts`, `pi-extension/src/daemon/*.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/daemon/*.test.ts`

## Current State
```ts
async function _cmdCreate(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* addDaemon + callSupervisor start */ }
async function _cmdRemove(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* supervisor unregister fallback */ }
async function _cmdDaemonStart(ctx: Pick<ExtensionContext, "ui">, id?: string): Promise<void> { /* callSupervisor */ }
async function _cmdCron(arg: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* tokenize + cron ops */ }
function _cmdInstall(ctx: Pick<ExtensionContext, "ui">, opts: { linkCli?: boolean } = {}): boolean { /* installService + linkCliBinaries */ }
export function _restartSupervisorCommand(platform: NodeJS.Platform, uid: number): RestartStep[] | null { /* OS command plan */ }
```

## Target State
```ts
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

export class CronCommands {
  async run(arg: string, ctx: UiCtx): Promise<void> { /* existing _cmdCron dispatcher */ }
}

export class ServiceCommands {
  install(ctx: UiCtx, opts: { linkCli?: boolean } = {}): boolean { /* existing _cmdInstall body */ }
  uninstall(ctx: UiCtx, opts: { linkCli?: boolean } = {}): void { /* existing _cmdUninstall body */ }
}

export function restartSupervisorCommand(platform: NodeJS.Platform, uid: number): RestartStep[] | null { /* existing pure body */ }
export function restartSupervisor(): void { /* existing side-effect body */ }
```

## Implementation Notes
- Do not move the already-good daemon implementation modules (`daemon/supervisor.ts`, `daemon/registry.ts`, `daemon/cron_registry.ts`, etc.) unless an import cycle requires a small type move.
- Move only command wrappers/parsers out of `index.ts`.
- Preserve exact user-facing messages. Existing tests assert substrings and the CLI is operator-facing.
- Keep fallback behavior when supervisor is offline: registry-only list, friendly `SupervisorOfflineError` messages, and registry-only remove fallback.
- Keep Windows-specific spawn/service safeguards intact by importing existing daemon/install helpers rather than rewriting them.

## Acceptance Criteria
- [ ] Daemon, cron, service, and supervisor-restart command wrappers no longer live in `index.ts`.
- [ ] `daemon/` modules remain the single source of daemon runtime behavior; command-surface files are thin orchestration adapters.
- [ ] `/remote-pi create/remove/daemons/daemon */cron/install/uninstall` preserve outputs and error handling.
- [ ] `_restartSupervisorCommand` remains exported compatibly (alias or testing harness) for existing tests.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test -- src/extension.test.ts src/daemon`, and `corepack pnpm build` pass.

## Rollback
Move the command wrapper classes back into `index.ts` and restore direct imports from `daemon/`. Because daemon runtime modules are not structurally changed, no supervisor state migration is involved.
