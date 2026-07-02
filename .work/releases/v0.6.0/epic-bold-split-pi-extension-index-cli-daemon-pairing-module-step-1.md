---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 1: Create the CommandSurface module shell and legacy dependency seam

**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / missing abstraction  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/src/extension/command_surface/legacy_deps.ts`, `pi-extension/src/extension/ports.ts`

## Current State
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

## Target State
```ts
// pi-extension/src/extension/command_surface.ts
export interface CommandSurfaceDeps {
  readonly registerAgentTools: (pi: ExtensionAPI) => void;
  readonly deployAgentNetworkSkill: () => void;
  readonly refreshPairingsCache: () => void;
  readonly registerCommands: (pi: ExtensionAPI) => void;
  readonly startDaemonMode: () => void;
}

export function createCommandSurface(deps: CommandSurfaceDeps): CommandSurfacePort {
  return {
    register(pi, _runtime) {
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

## Implementation Notes
- Introduce the behavior-preserving shell only. Moving command registration behind `_registerRemotePiCommands(pi)` is okay; moving command bodies is not part of this step.
- Use the `CommandSurfacePort` shape from the landed composition-root feature; do not invent a competing port.
- Keep the command-surface module side-effect free until `register(...)` is called.
- Preserve daemon-mode delayed `_cmdRoot` behavior and headless UI filtering.

## Acceptance Criteria
- [ ] A named command-surface module exists and satisfies `CommandSurfacePort`.
- [ ] `index.ts` delegates command-surface registration through `createLegacyCommandSurface()` / composition-root ports.
- [ ] `/remote-pi` and nested command registration count/names are unchanged.
- [ ] Daemon auto-init still runs only when `REMOTE_PI_DAEMON=1`.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

## Rollback
Inline `createCommandSurface(...).register(...)` back into the extension factory and delete the new command-surface shell. This wrapper-only step does not touch protocol, daemon, or pairing internals.

## Implementation notes
- Files changed: `pi-extension/src/extension/command_surface.ts`, `pi-extension/src/extension/command_surface/legacy_deps.ts`, `pi-extension/src/index.ts`.
- Tests added: none (wrapper-only shell; existing command registration tests remain the behavior guard).
- Verification: `corepack pnpm typecheck` passed from `pi-extension/`; `corepack pnpm test` was run and failed on pre-existing/environment UDS lock/listen failures (`EPERM` under `/tmp/claude/...`, cwd lock/leader-election suites), not on command-surface typing.
- Discrepancies from design: `resources_discover` stays registered in `index.ts` because the current `CommandSurfacePort` only owns registration side effects and command/daemon auto-init; the shell still deploys the skill and registers agent tools/commands.
- Adjacent issues parked: none.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Implementation commit `1e2c290` inspected; it adds the side-effect-free `createCommandSurface` module and the legacy seam, and `index.ts` delegates command-surface registration via `createLegacyCommandSurface().register(...)`. The shell uses the composition-root `CommandSurfacePort` signature and preserves delayed daemon-mode startup behind `REMOTE_PI_DAEMON=1`. Verification: `corepack pnpm typecheck` passed. `corepack pnpm test` was attempted and failed in unrelated environment-sensitive UDS suites (`listen EPERM` / cwd-lock / leader-election under `/tmp/claude/...`). Targeted `extension.test.ts` command-registration tests passed; one unrelated join/name-assigned test failed because UDS mesh join could not start in this harness.
