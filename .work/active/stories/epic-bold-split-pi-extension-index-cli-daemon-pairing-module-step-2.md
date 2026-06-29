---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-2
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
depends_on: [epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Replace duplicated slash-command registration with one command registry

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / single source of truth  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/commands.ts`, `pi-extension/src/extension/command_surface.ts`, `pi-extension/src/extension.test.ts`

## Current State
```ts
pi.registerCommand("remote-pi", {
  getArgumentCompletions: async (prefix) => [
    "setup", "status", "stop", "pair", "devices", "revoke", "set-relay",
    "peers", "create", "remove", "daemons",
    "daemon start", "daemon stop", "daemon restart", "daemon send", "daemon status",
    "cron", "cron add", "cron list", "cron remove", "cron enable", "cron disable", "cron run", "cron log",
    "install", "uninstall",
  ].filter((o) => o.startsWith(prefix)).map((o) => ({ value: o, label: o })),
  handler: async (args, ctx) => {
    const sub = args.trim();
    if      (sub === "")      { await _cmdRoot(ctx); }
    else if (sub === "setup") { await _cmdSetup(ctx); }
    // ...long if/else router...
    else                      { await _cmdRoot(ctx); }
  },
});

pi.registerCommand("remote-pi setup", { description: "Run the setup wizard and update local config", handler: async (_, ctx) => { _lastCtx = ctx; await _cmdSetup(ctx); } });
// ...19 more nested registrations...
```

## Target State
```ts
export interface RemotePiCommandSpec {
  readonly suffix: string;
  readonly description: string;
  readonly complete?: (prefix: string) => Promise<Array<{ value: string; label: string }>>;
  readonly run: (args: string, ctx: ExtensionCommandContext) => void | Promise<void>;
}

export function registerRemotePiCommands(pi: ExtensionAPI, specs: readonly RemotePiCommandSpec[]): void {
  pi.registerCommand("remote-pi", {
    description: "Connect (join local mesh + start relay), or run setup on first use",
    getArgumentCompletions: async (prefix) => completeRoot(prefix, specs),
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

## Implementation Notes
- Preserve the public command set exactly: `remote-pi`, `setup`, `status`, `stop`, `pair`, `devices`, `revoke`, `set-relay`, `peers`, `create`, `remove`, `daemons`, daemon subcommands, `cron`, `install`, `uninstall`.
- Preserve absent command behavior: `join`, `leave`, `relay start`, `config`, `start`, `list`, and `add-relay` remain unregistered.
- Preserve root-router fallback: unknown or empty root subcommands still call the root connect path.
- Keep `revoke` completions delegated to the same short-id completion callback.

## Acceptance Criteria
- [ ] Root command completions and nested registrations derive from one registry/spec table.
- [ ] The command registration test still sees exactly the same command names/count.
- [ ] Command descriptions remain unchanged for user-facing commands.
- [ ] Unknown root subcommands still fall back to the root command path.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

## Rollback
Restore the explicit `pi.registerCommand(...)` block and delete the registry helper. Command bodies remain untouched by this step.
