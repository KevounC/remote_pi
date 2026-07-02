---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
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

## Implementation notes
- Files changed: `pi-extension/src/extension/owner_multiplexer.ts`.
- Tests added: none (shell-only step; existing integration tests remain the behavior guard).
- Verification: `corepack pnpm typecheck` passed from `pi-extension/`; `corepack pnpm test` was run and failed on pre-existing/environment UDS lock/listen failures (`EPERM` under `/tmp/claude/...`, cwd lock/leader-election suites), not on owner-multiplexer shell typing.
- Discrepancies from design: composition-root `OwnerMultiplexerPort` currently exposes only `activeCount/attach/detach/broadcast/routeFrom/lateAttachTargets`, so the step-1 shell implements that landed shape and keeps richer pairing/storage dependencies out until later owner ingress steps.
- Adjacent issues parked: none.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Implementation commit `f593682` inspected. `owner_multiplexer.ts` compiles as a NodeNext ESM module and implements the landed composition-root `OwnerMultiplexerPort` shape (`activeCount`, `attach`, `detach`, `broadcast`, `routeFrom`, `lateAttachTargets`). This is a shell-only step and is not wired into `index.ts` yet, but the adapter is more than a stub for channel ownership: attach replaces stale channels, creates a typed channel via dependency injection, detach tears down and refreshes footer, and broadcast fans out best-effort. `routeFrom` remains a no-op because legacy per-channel routing is still supplied through `AttachOwnerInput.onMessage` until later steps move routing into the module. Verification: `corepack pnpm typecheck` passed. `corepack pnpm test` was attempted and failed in unrelated environment-sensitive UDS suites (`listen EPERM` / cwd-lock / leader-election under `/tmp/claude/...`).
