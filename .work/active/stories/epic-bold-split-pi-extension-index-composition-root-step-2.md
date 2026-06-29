---
id: epic-bold-split-pi-extension-index-composition-root-step-2
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-composition-root
depends_on: [epic-bold-split-pi-extension-index-composition-root-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Add the composition-root shell and lifecycle epoch

## Current State
`index.ts` registers Pi SDK hooks, commands, daemon auto-init, resources, tools, and shutdown handling directly inside the extension factory.

```ts
const extension: ExtensionFactory = (pi: ExtensionAPI): void => {
  _pi = pi;
  _messageApi = pi;
  _refreshPairingsCache();
  pi.on("resources_discover", () => ({ skillPaths: [skillsDir()] }));
  registerAgentTools(pi, () => _meshNode?.peer() ?? null);
  pi.on("input", (event) => { /* direct global mutation */ });
  pi.registerCommand("remote-pi", { /* direct command router */ });
};
```

## Target State
Introduce `pi-extension/src/extension/composition_root.ts`:

```ts
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
      registerLifecycleHooks(pi, ports, epoch);
      ports.commands.register(pi, this);
    },
    async dispose() {
      epoch.dispose();
      ports.session.clearStaleContexts();
      ports.relay.detachCrossPcBridge();
      ports.relay.stop();
    },
  };
}
```

Then `index.ts` becomes a factory that creates legacy ports and passes them to the runtime; large existing helper bodies remain in `index.ts` for now.

## Implementation Notes
- Preserve Pi hook registration order unless tests prove order is irrelevant.
- Epoch/disposal is owned by the composition root and must be checked after awaits in start/connect/join/bridge flows.
- Do not extract relay/owner/session internals in this story; only introduce the shell and connect it to current callbacks.

## Acceptance Criteria
- [ ] Composition-root module owns `register()`, `dispose()`, and epoch creation.
- [ ] Default export remains an `ExtensionFactory`.
- [ ] Existing extension registration tests still pass.
- [ ] Targeted test or assertion verifies `session_shutdown` marks the epoch before late async continuations publish state.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

## Risk
High: lifecycle registration order and shutdown races are sensitive.

## Rollback
Revert the composition-root module and restore inline extension-factory registration in `index.ts`.
