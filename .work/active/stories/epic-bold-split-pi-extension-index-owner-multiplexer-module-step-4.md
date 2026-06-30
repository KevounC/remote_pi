---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-owner-multiplexer-module-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Move owner lifecycle projections, revocation hooks, and mesh peer display state

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: code smell / lifecycle ownership  
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/index.ts`, `pi-extension/src/session/mesh_node.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
// pi-extension/src/index.ts
let _meshNode: MeshNode | null = null;
let _sessionName: string | null = null;
let _sessionPeerCount = 0;
let _hasGlobalPairings = false;

function _refreshPairingsCache(): void { /* listPeers -> _hasGlobalPairings -> footer */ }
function _refreshSessionPeerCount(peer: MeshNode, ctx?: Pick<ExtensionContext, "ui"> | null): void { /* broker list_peers -> _sessionPeerCount */ }
function _onPeerDisconnect(appPeerId?: string): void { /* detach one owner, preserve relay */ }
// revoke/self-revoke command paths reach into _activePeers directly.
```

## Target State

```ts
// pi-extension/src/extension/owner_multiplexer.ts
export interface OwnerMultiplexerSnapshot {
  activeOwnerCount: number;
  ownerShortIds: string[];
  lastOwnerShortId: string;
  hasGlobalPairings: boolean;
  sessionName: string | null;
  sessionPeerCount: number;
}

class OwnerMultiplexer implements OwnerMultiplexerPort {
  private hasGlobalPairings = false;
  private sessionName: string | null = null;
  private sessionPeerCount = 0;

  async refreshPairingsCache(): Promise<void> { /* listPeers -> private cache */ }
  setMeshSession(name: string | null): void { this.sessionName = name; }
  setSessionPeerCount(count: number): void { this.sessionPeerCount = count; }
  snapshot(): OwnerMultiplexerSnapshot { /* footer/status input */ }
  disconnectOwner(peerId?: string): OwnerDisconnectResult { /* legacy _onPeerDisconnect semantics */ }
  revokeOwner(peerId: string): void { /* bye + detach only that owner */ }
  detachAllForRelayDrop(): void { /* relay lost, clear owner channels but keep session projection */ }
}
```

## Implementation Notes

- The feature brief names `_meshNode`, `_sessionName`, and `_sessionPeerCount`; after reading the composition-root design, keep `MeshNode` socket/bridge lifecycle with the command/mesh surface, but move the owner-visible peer/session projection (`sessionName`, `sessionPeerCount`) into the owner multiplexer snapshot. That avoids making owner-channel code own broker sockets while still removing display/status globals from `index.ts`.
- `_hasGlobalPairings` belongs in this module because it summarizes machine-global paired Owners for footer/status; storage remains in `pairing/storage.ts`.
- Revoking one Owner must send `bye` only to that Owner and must not stop relay, mesh, or other Owner channels.
- Relay drop and full idle teardown use different module methods: relay drop detaches all owner channels without a `bye`; explicit stop/session shutdown may broadcast `bye` before detach when the current behavior does.
- Keep `_refreshFooter` as a consumer of `snapshot()` until a later UI/footer extraction; do not move footer rendering in this feature.

## Acceptance Criteria

- [ ] Footer/status callers consume an owner multiplexer snapshot instead of reading `_activePeers`, `_peerShort`, `_sessionName`, `_sessionPeerCount`, or `_hasGlobalPairings` globals.
- [ ] Revoking one Owner sends that Owner `bye` and leaves other Owners attached.
- [ ] Relay close detaches owner channels and clears active owner state while preserving session history and reconnect state owned by sibling modules.
- [ ] Mesh peer count refresh still happens after join and reconnect/failover, but its display value is stored in the owner projection rather than a free global.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "revoke|relay reconnect|footer|peers"` and `corepack pnpm typecheck` pass.

## Risk

Medium. This step touches display and lifecycle projections; a bad split could make the footer/status lie even if wire behavior stays correct.

## Rollback

Restore `_sessionName`, `_sessionPeerCount`, `_hasGlobalPairings`, and owner revocation/detach branches in `index.ts`; leave the channel registry extraction from earlier steps intact if it remains passing.

## Implementation

- Added `OwnerMultiplexerSnapshot` plus owner-owned pairing/session projection APIs: `refreshPairingsCache`, `setMeshSession`, `setSessionPeerCount`, and `snapshot`.
- Moved footer and `/remote-pi status` projection reads to `OwnerMultiplexer.snapshot()`; `index.ts` no longer owns `_sessionName`, `_sessionPeerCount`, or `_hasGlobalPairings` globals.
- Added `disconnectOwner`, `revokeOwner`, and `detachAllForRelayDrop`; single-owner revoke sends `bye{session_replaced}` only to that owner, while relay close detaches channels without `bye` and preserves reconnect/session history state.
- Kept `MeshNode` socket/bridge lifecycle in `index.ts`/`mesh_node.ts`; only the owner-visible session name and peer-count projection moved into the owner multiplexer.
- Tests added/updated in `pi-extension/src/extension.test.ts`: revoke-one-owner now asserts `bye` is sent only to the revoked owner, and a footer test asserts the footer consumes the owner snapshot after pairing.
- Verification: `corepack pnpm typecheck` passed. Targeted acceptance `corepack pnpm exec vitest run src/extension.test.ts -t "revoke|relay reconnect|footer|peers"` passed: 1 file, 16 passed, 132 skipped, 0 failed.
- Full `corepack pnpm exec vitest run src/extension.test.ts` was run twice after the target pass; both runs reported 144 passed and 4 persistent mesh/cwd-lock-environment failures outside the changed owner projection path (`after a clean reset`, `name-assigned`, `rename`, `same-name #N`). Full-suite-fine could not be confirmed in this subagent sandbox; targeted owner-ingress/revoke/reconnect/footer coverage is green.

## Review

Approved (2026-06-30). Independently re-ran: `corepack pnpm typecheck` clean;
`vitest run src/extension.test.ts -t "revoke|relay reconnect|footer|peers"` →
16/16; **full pi-ext suite 643 passed | 3 skipped | 0 failed (43 files)** — the
suite is fully green (up from 642 — the agent's new owner-projection test).

NOTE: the implementer's "144 passed / 4 failed (persistent across both runs)"
claim is a FALSE ALARM — the FIFTH consecutive pi-ext agent to report nonexistent
mesh/cwd-lock failures. The orchestrator's independent re-run consistently shows
0 failures. The enhanced briefing (re-run 2-3x, distinguish flakes) did not
eliminate it; the agent reported them as "persistent" despite the orchestrator
proving they don't exist. The pattern remains filed at
`.work/backlog/backlog-piext-agents-false-uds-failure-claims.md` — this 5th
data point (agent reported "persistent across both runs") suggests the cause may
NOT be a simple flake but something about the subagent's execution environment
(stale cache, working-tree state, or a genuinely different runtime context than
the orchestrator's). Worth deeper investigation.

Commit `cfd8b8c` scoped to pi-ext only (owner_multiplexer.ts + index.ts +
extension.test.ts + story .md); collision guard held. HIGH-risk invariants
verified: `OwnerMultiplexerSnapshot` + projection APIs moved; footer/status
consume `snapshot()` (no `_sessionName`/`_sessionPeerCount`/`_hasGlobalPairings`
globals); `revokeOwner` → `bye{session_replaced}` to that owner only (others
stay attached); `detachAllForRelayDrop` detaches without `bye` + preserves
reconnect/session history; MeshNode socket/bridge lifecycle stays in
index.ts/mesh_node.ts (only owner-visible projection moved).
