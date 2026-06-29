---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-1
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Introduce the OwnerMultiplexerPort adapter shell

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / lifecycle ownership  
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/index.ts`

## Current State

```ts
// pi-extension/src/index.ts
const _activePeers = new Map<string, PlainPeerChannel>();
let _peerShort = "";
let _hasGlobalPairings = false;

function _broadcastToActive(msg: ServerMessage): void { /* map fanout */ }
function _attachOwner(relay: RelayClient, appPeerId: string, peerName: string): PlainPeerChannel { /* constructs PlainPeerChannel */ }
function _installAutoListener(relay: RelayClient): () => void { /* pair/known/unknown ingress */ }
```

## Target State

```ts
// pi-extension/src/extension/owner_multiplexer.ts
export interface OwnerMultiplexerDeps {
  createChannel(input: CreateOwnerChannelInput): PeerChannelHandle;
  findKnownPeer(appPeerId: string): Promise<PeerRecord | null>;
  addPeer(record: PeerRecord): Promise<void>;
  listPeers(): Promise<PeerRecord[]>;
  consumePairToken(token: string): PairTokenStatus;
  makePairOk(input: PairOkInput): ServerMessage;
  notify(message: string, type?: "info" | "warning" | "error"): void;
  refreshFooter(): void;
  routeClientMessage(sender: PeerChannel, message: ClientMessage): void;
}

export function createOwnerMultiplexerPort(deps: OwnerMultiplexerDeps): OwnerMultiplexerPort {
  const channels = new Map<string, PeerChannelHandle>();
  let peerShort = "";
  let hasGlobalPairings = false;
  // activeCount/attach/detach/broadcast/routeFrom/lateAttachTargets implemented here.
}
```

## Implementation Notes

- Use the `OwnerMultiplexerPort` exported by the composition-root work; do not create a parallel interface with the same name.
- Keep the shell mostly type-first: dependency injection, private map state, and method skeletons that can wrap legacy helpers before bodies move.
- Model channel identity as the current runtime invariant: one live channel per `(owner peer id, current relay room)` at the extension. Because a started extension runtime owns one room at a time, the internal map key can remain `appPeerId`; document that relay fanout to multiple Owner devices remains outside the module.
- Patchbay guard: dependencies are generic owner-channel and pairing primitives, not Pi-SDK globals or fork-specific god-file names.

## Acceptance Criteria

- [ ] `owner_multiplexer.ts` exists and compiles as an ESM/NodeNext module.
- [ ] It implements the composition-root `OwnerMultiplexerPort` shape without changing public protocol, CLI output, or relay frames.
- [ ] `_activePeers`, `_peerShort`, and `_hasGlobalPairings` have a named target owner in the new module, even if legacy wrappers still feed them during this step.
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.

## Risk

Medium. The wrong port shape could force sibling modules to depend on owner internals or leak relay/client details back into the composition root.

## Rollback

Delete `owner_multiplexer.ts` and remove any type-only imports or legacy adapter references added in this step. Because this is a shell step, rollback should not touch wire behavior.
