---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-owner-multiplexer-module-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 2: Move owner channel registry and fanout into the module

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / missing abstraction  
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/index.ts`, `pi-extension/src/transport/peer_channel.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
// pi-extension/src/index.ts
function _attachPeerChannel(appPeerId: string, channel: PlainPeerChannel): void {
  _activePeers.set(appPeerId, channel);
  _peerShort = appPeerId.slice(0, 8);
  if (_turnActive) _peersAttachedDuringTurn.add(appPeerId);
}

function _detachPeerChannel(appPeerId: string): void {
  const ch = _activePeers.get(appPeerId);
  if (!ch) return;
  try { ch.detach(); } catch { /* best-effort */ }
  _activePeers.delete(appPeerId);
  const next = _activePeers.keys().next().value;
  _peerShort = next ? next.slice(0, 8) : "";
}

function _broadcastToActive(msg: ServerMessage): void {
  for (const ch of _activePeers.values()) {
    try { ch.send(msg); } catch { /* best-effort per channel */ }
  }
}
```

## Target State

```ts
// pi-extension/src/extension/owner_multiplexer.ts
class OwnerMultiplexer implements OwnerMultiplexerPort {
  private readonly channels = new Map<string, PeerChannelHandle>();
  private peerShort = "";
  private lateAttachPeerIds = new Set<string>();

  activeCount(): number { return this.channels.size; }
  peerHint(): string { return this.peerShort; }

  attach(input: AttachOwnerInput): PeerChannel {
    this.detach(input.peerId);
    const channel = this.deps.createChannel({
      peerId: input.peerId,
      roomId: input.roomId,
      onMessage: (message) => this.routeFrom(channel, message),
      onDisconnect: () => this.detach(input.peerId, "disconnect"),
    });
    this.channels.set(input.peerId, channel);
    this.peerShort = input.peerId.slice(0, 8);
    if (input.turnActive) this.lateAttachPeerIds.add(input.peerId);
    return channel;
  }

  detach(peerId: string): void { /* detach one, preserve others */ }
  detachAll(reason?: ByeReason): void { /* optional bye then detach every channel */ }
  broadcast(message: ServerMessage): void { /* best-effort fanout to every channel */ }
  lateAttachTargets(): PeerChannel[] { /* consume marked channels */ }
}
```

## Implementation Notes

- Preserve idempotent reattach: attaching the same owner peer id first detaches the stale channel to avoid duplicate relay listeners.
- Preserve best-effort fanout: one owner's `send()` failure must not prevent delivery to other owners.
- Preserve derived `paired` state: callers derive it from `activeCount() > 0`, not from a third `_state` enum value.
- Keep `PlainPeerChannel` as the low-level relay-backed channel; the owner module owns channel lifetime, not websocket auth or liveness.
- Keep relay broadcast semantics unchanged: the extension sends one per-owner outbound envelope through each live channel; the relay remains responsible for lower-level connection fanout and skip-sender behavior.

## Acceptance Criteria

- [ ] `_activePeers` map mutation is replaced by OwnerMultiplexer methods.
- [ ] `broadcast()` still sends to every attached owner and isolates per-channel exceptions.
- [ ] Detaching one owner leaves other owners connected and leaves relay started.
- [ ] Late-attach tracking still records owners attached during an active turn for catch-up history.
- [ ] Existing multi-channel tests for two owners, `agent_chunk` broadcast, revoke-one-owner, and queued-message fanout pass.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "multi-channel broadcast"` and `corepack pnpm typecheck` pass.

## Implementation

- Added `OwnerMultiplexer` as the owner-channel registry and fanout owner. `index.ts` no longer owns `_activePeers`, `_peerShort`, `_attachPeerChannel`, `_detachPeerChannel`, `_broadcastToActive`, or `_anyPeerActive`; derived paired state now reads `OwnerMultiplexer.activeCount() > 0`.
- Preserved idempotent reattach by detaching an existing channel for the same owner before installing the new `PlainPeerChannel`, preserving one relay listener per owner peer id.
- Preserved best-effort fanout by isolating each `send()` in `OwnerMultiplexer.broadcast()`; detaching one owner preserves other owner channels and keeps relay state `started`.
- Preserved late-attach behavior by passing active-turn state into owner attach and keeping the existing turn projection `peer_attached` event for catch-up history flushes.
- Verification:
  - `corepack pnpm typecheck`: pass.
  - `corepack pnpm exec vitest run src/extension.test.ts -t "multi-channel broadcast"`: pass — 28 passed, 119 skipped, 0 failed.
  - `corepack pnpm exec vitest run src/extension.test.ts`: attempted — 142 passed, 5 failed. The failures are all local mesh/UDS setup cases (`session_shutdown DURING _cmdStart...`, clean reset mesh join, name-assigned join, rename live, same-folder same-name lock). A direct Node UDS bind in this sandbox fails with `listen EPERM`, so these are the mesh UDS cases unable to bind in the current shell environment; no multi-owner/owner-multiplexer acceptance tests failed.

## Risk

High. Listener leaks or accidentally reverting to a singleton channel would duplicate incoming messages or disconnect the wrong owner.

## Rollback

Restore `_activePeers`, `_peerShort`, `_attachPeerChannel`, `_detachPeerChannel`, `_broadcastToActive`, and `_anyPeerActive` in `index.ts`; leave the shell unused if it is otherwise harmless.

## Review

Approved (2026-06-30) with HIGH-risk verification. Independently re-ran:
`corepack pnpm typecheck` clean; `vitest run src/extension.test.ts -t
"multi-channel broadcast"` → 28/28; **full `extension.test.ts` 147/147**;
**full pi-ext suite 642 passed | 3 skipped | 0 failed (43 files)** — the suite
is fully green.

NOTE: the implementer's "5 failed UDS/mesh EPERM" claim is a FALSE ALARM (same
pattern as late-attach-step-3). Orchestrator's independent re-run shows zero
failures. The UDS ceiling WAS lifted earlier this session and the test-debt
cleared; baseline is zero failures. The implementer likely hit a transient/flaky
run (parallel-agent working-tree interference or mid-write state) and
mis-attributed real failures to the env. No actual regression.

Commit `9b81352` scoped to owner_multiplexer.ts + index.ts + extension.test.ts +
story .md; collision guard held (sole pi-ext writer). HIGH-risk invariants
verified directly in code + tests:
- **Idempotent reattach**: existing channel for same owner detached before
  installing new PlainPeerChannel (one relay listener per owner peer id).
- **Best-effort fanout isolation**: `broadcast()` wraps each `channel.send()`
  in its own try/catch — one owner's failure doesn't block others; detaching
  one owner preserves others + relay `started`.
- **Late-attach tracking preserved**: active-turn state passed into attach;
  turn projection `peer_attached` event kept for catch-up history flushes.
- `_activePeers`/`_peerShort`/attach/detach/broadcast/anyPeerActive replaced by
  OwnerMultiplexer methods; `paired` derived from `activeCount() > 0`.
