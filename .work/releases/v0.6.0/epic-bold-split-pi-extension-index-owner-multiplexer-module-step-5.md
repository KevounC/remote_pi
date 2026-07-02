---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-5
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-owner-multiplexer-module-step-4]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 5: Lock compatibility exports and owner-multiplexer tests

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: pattern drift / dead weight prevention  
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/extension/testing.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
// pi-extension/src/index.ts
export function _getActivePeerCountForTest(): number { return _activePeers.size; }
export function _hasActivePeerForTest(appPeerIdStd: string): boolean { return _activePeers.has(appPeerIdStd); }
export function _onPeerDisconnect(appPeerId?: string): void { /* direct globals */ }
export function routeClientMessage(msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void {
  const fallback = [..._activePeers.values()].pop();
  if (!fallback) return;
  _routeClientMessageFrom(fallback, msg, ctx);
}
```

## Target State

```ts
// pi-extension/src/extension/testing.ts
export interface OwnerMultiplexerTestHarness {
  activeOwnerCount(): number;
  hasOwner(peerId: string): boolean;
  disconnectOwner(peerId?: string): void;
  fallbackRoute(message: ClientMessage, ctx: Pick<ExtensionContext, "abort">): void;
}

// pi-extension/src/index.ts
export const _getActivePeerCountForTest = () => ownerHarness.activeOwnerCount();
export const _hasActivePeerForTest = (peerId: string) => ownerHarness.hasOwner(peerId);
export const _onPeerDisconnect = (peerId?: string) => ownerHarness.disconnectOwner(peerId);
export const routeClientMessage = (msg: ClientMessage, ctx: Pick<ExtensionContext, "abort">) =>
  ownerHarness.fallbackRoute(msg, ctx);
```

## Implementation Notes

- Keep existing test exports as aliases so current tests and any out-of-tree operator scripts do not break during the split.
- Add focused unit tests for `OwnerMultiplexer` with fake channel handles: attach same owner replaces the channel, broadcast fans out to all owners, detach one preserves the other, and malformed/unknown ingress is ignored or sender-only errored according to current behavior.
- Keep integration tests for app-visible behavior in `extension.test.ts`; do not replace them with purely structural tests.
- Do not delete legacy comments/history by mass churn. Move only comments that defend the current owner-multiplexer invariant.

## Acceptance Criteria

- [ ] Existing `_getActivePeerCountForTest`, `_hasActivePeerForTest`, `_onPeerDisconnect`, and `routeClientMessage` imports still work.
- [ ] New owner-multiplexer unit tests cover attach/detach/broadcast/reconnect-ingress without booting the full extension.
- [ ] Integration tests still cover public behavior: N owners, sender-specific `session_sync`, all-owner rebroadcast, revoke-one-owner, relay drop cleanup.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass.

## Risk

Medium. Test harness churn can accidentally weaken the multi-owner contract or hide a regression behind aliases.

## Implementation

- Added `pi-extension/src/extension/testing.ts` with `OwnerMultiplexerTestHarness` and a harness factory for compatibility aliases.
- Switched `pi-extension/src/index.ts` compatibility exports (`_getActivePeerCountForTest`, `_hasActivePeerForTest`, `_onPeerDisconnect`, `routeClientMessage`) to delegate through `ownerHarness` while preserving the runtime disconnect side effects.
- Added focused `OwnerMultiplexer` unit tests using fake owner channels: same-owner reattach replaces the stale channel, broadcast fans out to all attached owners, detach-one preserves the other, known-owner reconnect ingress attaches and routes the triggering message, and malformed/unknown ingress is ignored or sender-only errored.
- Preserved existing `extension.test.ts` integration coverage; no structural replacement of app-visible multi-owner behavior tests.

Verification:

- `corepack pnpm typecheck`: pass (`tsc --noEmit`).
- `corepack pnpm exec vitest run src/extension.test.ts -t "revoke|relay reconnect|footer|peers|multi-channel"`: pass — 1 file passed; 43 passed, 105 skipped (148 total).
- `corepack pnpm exec vitest run src/extension/owner_multiplexer.test.ts`: pass — 1 file passed; 5 passed.
- `corepack pnpm exec vitest run src/extension/`: pass — 3 files passed; 8 passed.
- `corepack pnpm build`: pass (`tsc`).
- `corepack pnpm test`: observed the known false-failure signature in this subagent environment — 39 files passed, 5 failed; 582 passed, 66 failed, 3 skipped (651 total). Failing test names matched the pre-declared mesh/cwd-lock false-alarm group (`cwd_lock`, `leader_election`, `session/e2e`, `supervisor`) and are not attributable to this owner-multiplexer change.

## Rollback

Restore test exports to direct `index.ts` globals and remove the owner harness aliases. Keep behavior tests unchanged so rollback still proves the old path.

## Review

Approved (2026-06-30). Independently re-ran: `corepack pnpm typecheck` clean;
`corepack pnpm build` clean; `vitest run src/extension/owner_multiplexer.test.ts`
→ 5/5; `vitest run src/extension.test.ts -t "revoke|relay reconnect|footer|peers|
multi-channel"` → 43/43; **full pi-ext suite 648 passed | 3 skipped | 0 failed
(44 files)** — fully green (up from 643 — the agent's 5 new unit tests).

NOTE: the implementer's full-`pnpm test` reported "582 passed | 66 failed" but
CORRECTLY identified it as the known false-failure signature ("failing names
matched the pre-declared mesh/cwd-lock false-alarm group, not this change").
The enhanced briefing worked — this is the first pi-ext agent to recognize the
pattern instead of chasing it. The orchestrator's independent vitest run shows
0 failures. (The 66-count is higher than prior agents' 4-5, likely because
`pnpm test` includes more than the vitest suite or hit a worse transient state;
regardless, the targeted signals were all green and the agent correctly did not
attribute the failures to its own change.)

Commit `7394dd4` scoped to pi-ext only (testing.ts + owner_multiplexer.test.ts +
index.ts + story .md); collision guard held. Acceptance criteria verified:
`OwnerMultiplexerTestHarness` + `ownerHarness` aliases delegate the 4 test exports
(existing imports still work); 5 focused unit tests (fake channels, no full
extension boot) cover same-owner reattach-replaces-channel, broadcast fanout,
detach-one-preserves-other, known-owner reconnect ingress attaches+routes,
malformed/unknown ingress ignored or sender-only errored; integration tests
preserved. **owner-multiplexer arc complete (5/5).**
