---
id: epic-bold-split-pi-extension-index-composition-root-step-5
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-composition-root
depends_on: [epic-bold-split-pi-extension-index-composition-root-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation
- Added `RemotePiTestHarness` and `createRemotePiTestHarness` in `pi-extension/src/extension/testing.ts`.
- Added exported `remotePiTestHarness` in `pi-extension/src/index.ts` and aliased `_connectForTest`, `_stopForTest`, `_getState`, and `routeClientMessage` through that harness while preserving their legacy names.
- Kept `probeListPeers` exported from `extension/probe_list_peers.ts`; it had already been moved as a pure helper and this step preserved that seam.
- Updated `pi-extension/src/extension.test.ts` so the start/state smoke test uses the named harness while checking legacy `_getState` still matches the harness state.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; focused harness test `corepack pnpm exec vitest run src/extension.test.ts -t "start: idle"` passed (1 passed, 148 skipped). Full `src/extension.test.ts` run reported 145 passed / 4 failed out of 149; the failures match the confirmed known false-alarm group (`after a clean reset`, `name-assigned`, `rename:<name>`, same-name cwd-lock), so they were not chased.

## Review

Approved (2026-06-30). Independently re-ran: `corepack pnpm typecheck` clean;
**full pi-ext suite 651 passed | 3 skipped | 0 failed (44 files)** — fully green.

NOTE: the implementer CORRECTLY identified the false-failure pattern (6th
consecutive pi-ext agent to do so) — reported the full-suite "4 failed" as
"matching the confirmed known false-alarm group (`after a clean reset`,
`name-assigned`, `rename:<name>`, same-name cwd-lock), so they were not chased."

Commit `1c03e76` scoped to pi-ext only (testing.ts + index.ts + extension.test.ts).
Harness verified: `RemotePiTestHarness` + `createRemotePiTestHarness` added;
legacy `_connectForTest`/`_stopForTest`/`_getState`/`routeClientMessage` aliased
through the harness (names preserved, not deleted); `probeListPeers` kept as
pure-helper export; extension.test.ts start/state smoke uses the named harness
while still checking legacy `_getState` parity. **composition-root arc complete (5/5).**
