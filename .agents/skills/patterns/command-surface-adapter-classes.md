# Pattern: Command-Surface Adapter Classes

## Rationale

The extension’s command handling is split into small adapter classes (`*Commands`) in
`pi-extension/src/extension/command_surface`, each focused on one command domain
(daemon, cron, pairing, relay, service, local mesh, control). Each class owns
parsing/dispatch for its verb surface and delegates real effects to injected
dependencies.

This pattern appears across a cluster of command modules and supports:
- isolated unit-test strategy per domain,
- small API surface per command family,
- stable command orchestration (`registerRemotePiCommands`) with low coupling.

## When to use

Use this pattern when a command surface grows beyond a few verbs and requires
cohesive parsing and side-effect orchestration.

## When not to use

Avoid it for one-off commands that are purely internal plumbing and do not justify
an adapter surface.

## Examples

### Example 1: `DaemonCommands` adapter

**File:** `pi-extension/src/extension/command_surface/daemon_commands.ts:25`

```ts
export class DaemonCommands {
  async create(arg: string, ctx: UiCtx): Promise<void> { ... }
  async remove(arg: string, ctx: UiCtx): Promise<void> { ... }
  async start(ctx: UiCtx, id?: string): Promise<void> { ... }
}
```

### Example 2: `CronCommands` adapter with internal normalization helpers

**File:** `pi-extension/src/extension/command_surface/cron_commands.ts:16`

```ts
export class CronCommands {
  async run(arg: string, ctx: UiCtx): Promise<void> {
    const trimmed = arg.trim();
    const sub = (sp === -1 ? trimmed : trimmed.slice(0, sp)).toLowerCase();
    switch (sub) { ... }
  }

  private async add(rest: string, ctx: Pick<ExtensionContext, "ui">): Promise<void> { ... }
}
```

### Example 3: `LocalMeshCommands` composes sub-adapters + delegates work

**File:** `pi-extension/src/extension/command_surface/local_mesh_commands.ts:62`

```ts
export class LocalMeshCommands {
  private readonly controlCommands: ControlCommands;

  constructor(private readonly deps: LocalMeshCommandsDeps) {
    this.controlCommands = new ControlCommands({
      getState: deps.getState,
      isDisposed: deps.isDisposed,
      meshNode: deps.meshNode,
      controlCtx: deps.controlCtx,
      startRelay: deps.startRelay,
      stopRelay: deps.stopRelay,
      emitRelayState: deps.emitRelayState,
      notify: deps.notify,
      sendPiMessage: deps.sendPiMessage,
    });
  }
}
```

### Common violations

- Mixing transport/session internals and command parsing in one monolithic `index.ts`
  handler.
- Mutating global state directly from command methods without injecting focused
  collaborators.
- Exposing command handlers without explicit argument parsing boundaries.

## Index entry

- **command-surface-adapter-classes**: Keep command-surface logic in thin, dependency-injected adapter classes.
