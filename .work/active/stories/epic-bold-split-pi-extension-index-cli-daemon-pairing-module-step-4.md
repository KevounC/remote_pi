---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
depends_on: [epic-bold-split-pi-extension-index-cli-daemon-pairing-module-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Move relay-facing command handlers and QR pairing coordinator behind owner/session ports

**Priority**: High  
**Risk**: High  
**Source Lens**: missing abstraction / lifecycle ownership  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/extension/command_surface/pairing_commands.ts`, `pi-extension/src/extension/command_surface/pairing_coordinator.ts`, `pi-extension/src/extension/command_surface/relay_commands.ts`, `pi-extension/src/pairing/qr.ts`, `pi-extension/src/pairing/storage.ts`, `pi-extension/src/extension.test.ts`

## Current State
```ts
let _stopAutoListener: (() => void) | null = null;
let _cachedEd25519: Ed25519Keypair | null = null;
let _selfRevoke: SelfRevoke | null = null;

async function _cmdStart(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* keyring, room_meta, RelayClient.connect, SelfRevoke, bridge attach */ }
async function _cmdPair(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> { /* issue QR token + send pair-code */ }
async function _cmdList(ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* listPeers */ }
async function _cmdRevoke(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* removePeer + detach channel */ }
function _installAutoListener(relay: RelayClient): () => void { /* outer decode, pair_request, known-peer reconnect */ }
async function _handlePairRequest(relay: RelayClient, appPeerId: string, inner: PairRequest): Promise<void> { /* token, addPeer, pair_ok */ }
```

## Target State
```ts
export class PairingCoordinator {
  private cachedEd25519: Ed25519Keypair | null = null;
  private stopAutoListener: (() => void) | null = null;
  private selfRevoke: SelfRevoke | null = null;

  async startRelay(ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* existing _cmdStart behavior */ }
  async showPairQr(ctx: Pick<ExtensionContext, "ui" | "cwd">, args = ""): Promise<void> { /* existing _cmdPair behavior */ }
  async listDevices(ctx: Pick<ExtensionContext, "ui">): Promise<void> { /* existing _cmdList behavior */ }
  async revokeDevice(arg: string, ctx: Pick<ExtensionContext, "ui" | "cwd">): Promise<void> { /* existing _cmdRevoke behavior */ }
  installAutoListener(relay: RelayClient): () => void { /* existing listener, but calls this.handlePairRequest(...) */ }
  async handlePairRequest(relay: RelayClient, appPeerId: string, inner: PairRequest): Promise<void> { /* token + addPeer + pair_ok */ }
}

const channel = deps.owners.attach({
  relay,
  appPeerId,
  peerName: inner.device_name,
  roomId: deps.currentRoomId() ?? roomIdFor(cwd, sessionName),
  routeMessage: (sender, msg) => deps.session.handleClientMessage(sender, msg),
});
```

## Implementation Notes
- Move `_cachedEd25519`, `_stopAutoListener`, and `_selfRevoke` into the pairing/relay command coordinator.
- Preserve keyring behavior exactly: transient keyring failures still surface the current warning and must not generate a new identity on macOS/Windows.
- Preserve room identity invariants: room id derives from `(cwd, displayName)`, QR `rm` matches relay hello room, and `pair_ok.room_id` uses the same fallback.
- Preserve auto-listener semantics: attached owners are ignored by the listener; known peers reconnect without QR; unknown non-pair messages receive `unknown_peer`; `pair_request` token errors return the same `pair_error` codes/messages.
- Pairing may call `OwnerMultiplexerPort.attach(...)`, but it must not mutate `_activePeers` directly after this step.
- Keep `SelfRevoke` callback behavior: revoke only the matching owner, refresh pairings cache/footer, emit `remote-pi:mesh-revoked`, and update siblings through the appropriate dependency.

## Acceptance Criteria
- [ ] `_cachedEd25519`, `_stopAutoListener`, and `_selfRevoke` no longer live in `index.ts`.
- [ ] `/remote-pi pair`, `/remote-pi devices`, `/remote-pi revoke`, `/remote-pi set-relay`, relay start/reconnect, and QR copy-paste payloads preserve behavior.
- [ ] Pair request success/error/reconnect tests still pass, including `pair_ok` fields `session_name`, `session_started_at`, `session_id`, `room_id`, `harness`, and `hostname`.
- [ ] The module delegates owner channel attachment/routing through owner/session ports or legacy owner/session adapters.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts src/pairing/qr.test.ts src/pairing/storage.test.ts` pass.

## Rollback
Move the relay/pairing command bodies and private state back to `index.ts`, then restore direct `_attachOwner` / `_routeClientMessageFrom` calls. Storage and QR helper modules are not changed by this step, so persisted data rollback is not needed.
