---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-owner-multiplexer-module-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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

## Rollback

Restore test exports to direct `index.ts` globals and remove the owner harness aliases. Keep behavior tests unchanged so rollback still proves the old path.
