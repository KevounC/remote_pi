---
id: epic-bold-split-pi-extension-index-composition-root-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-composition-root
depends_on: [epic-bold-split-pi-extension-index-composition-root-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Lock compatibility seams and test-harness exports

## Current State
Tests and some helper paths import many private helpers directly from `index.ts`:

```ts
export async function _connectForTest(ctx: unknown): Promise<void> { /* ... */ }
export function _getState(): "idle" | "started" | "paired" { /* ... */ }
export function routeClientMessage(msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void { /* ... */ }
export async function probeListPeers(sockPath: string, timeoutMs = 2000): Promise<string[] | null> { /* ... */ }
```

These exports make refactoring harder because tests patch globals instead of going through a named runtime harness.

## Target State
Add a compatibility harness while keeping legacy exports as aliases:

```ts
// pi-extension/src/extension/testing.ts
export interface RemotePiTestHarness {
  connect(ctx: unknown): Promise<void>;
  stop(ctx: unknown): Promise<void>;
  state(): "idle" | "started" | "paired";
  routeClientMessage(message: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void;
}
```

```ts
// pi-extension/src/index.ts
export { probeListPeers } from "./extension/probe_list_peers.js";
export const _connectForTest = legacyHarness.connect;
export const _stopForTest = legacyHarness.stop;
export const _getState = legacyHarness.state;
export const routeClientMessage = legacyHarness.routeClientMessage;
```

## Implementation Notes
- Keep existing test imports working; do not delete `_fooForTest` exports in this feature.
- New tests should prefer the harness, so future sibling module extraction does not need to patch module globals.
- Move only pure helpers such as `probeListPeers` if doing so is behavior-preserving.

## Acceptance Criteria
- [ ] Existing tests import and pass without mass rewrites.
- [ ] New/updated tests can instantiate or observe the composition root through a named harness.
- [ ] Public package behavior and CLI exports are unchanged; internal test exports are compatibility aliases.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass.

## Risk
Medium: changing exports can break tests or downstream private users if aliases are missed.

## Rollback
Remove the harness wrapper and restore direct `_fooForTest` function exports in `index.ts`.
