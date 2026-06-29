---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
depends_on: [epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Move setup, local-mesh command lifecycle, and RPC control into CommandSurface

**Priority**: High  
**Risk**: High  
**Source Lens**: lifecycle ownership / code smell  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/src/extension/command_surface/local_mesh_commands.ts`, `pi-extension/src/extension/command_surface/control_commands.ts`, `pi-extension/src/extension/probe_list_peers.ts`, `pi-extension/src/extension.test.ts`, `pi-extension/src/session/e2e.test.ts`

## Current State
```ts
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

## Target State
```ts
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
```

## Implementation Notes
- Move `_cwdLock` and `_lockedName` into the command-surface/local-mesh class. Keep compatibility test exports as aliases until the whole split lands.
- Preserve all race guards that check `_disposed` after `_cmdJoin`/`_cmdStart` awaits. If composition-root exposes a runtime epoch, depend on it rather than a raw boolean.
- Command surface may own starting/stopping the local mesh because `/remote-pi` and daemon mode invoke it, but bridge attachment should remain delegated through relay/owner/session ports as they land.
- Extract `probeListPeers` as a pure utility and re-export from `index.ts` for existing `session/e2e.test.ts` imports.

## Acceptance Criteria
- [ ] `_cwdLock` and `_lockedName` are private fields of the command-surface/local-mesh controller.
- [ ] `/remote-pi`, `/remote-pi setup`, `/remote-pi stop`, `/remote-pi peers`, control `relay:*`, and control `rename:*` preserve current notifications and state transitions.
- [ ] `probeListPeers` lives outside `index.ts` and is re-exported compatibly.
- [ ] Existing stale/shutdown race tests around `_cmdJoin`, `_cmdStart`, `session_shutdown`, `CTRL_PREFIX`, and rename still pass.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts src/session/e2e.test.ts` pass.

## Rollback
Move the local-mesh/control bodies and test aliases back to `index.ts`; because state fields move together, rollback is a file-level revert for the new local-mesh command files.
