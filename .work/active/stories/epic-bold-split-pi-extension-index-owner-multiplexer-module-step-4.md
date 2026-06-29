---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-owner-multiplexer-module-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
