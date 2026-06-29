---
id: epic-bold-split-pi-extension-index-owner-multiplexer-module-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-owner-multiplexer-module
depends_on: [epic-bold-split-pi-extension-index-owner-multiplexer-module-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Move owner ingress, pairing, and reconnect attach decisions

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / fail-fast boundary  
**Files**: `pi-extension/src/extension/owner_multiplexer.ts`, `pi-extension/src/index.ts`, `pi-extension/src/pairing/storage.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
// pi-extension/src/index.ts
function _installAutoListener(relay: RelayClient): () => void {
  const onMsg = async (line: string) => {
    const outer = JSON.parse(line) as { peer?: string; ct?: string };
    if (_activePeers.has(outer.peer)) return;
    const inner = JSON.parse(Buffer.from(outer.ct, "base64").toString("utf8")) as ClientMessage;
    if (inner.type === "pair_request") await _handlePairRequest(relay, appPeerId, inner);
    const known = await _findKnownPeer(appPeerId);
    if (known) {
      const channel = _attachOwner(relay, appPeerId, known.name);
      _routeClientMessageFrom(channel, inner, _lastEventCtx ?? _lastCtx ?? _noopCtx);
    }
  };
  relay.on("message", onMsg);
  return () => relay.off("message", onMsg);
}
```

## Target State

```ts
// pi-extension/src/extension/owner_multiplexer.ts
async handleOuterLine(input: OwnerOuterLineInput): Promise<void> {
  const outer = decodeOuterEnvelope(input.line);
  if (!outer) return;
  if (this.channels.has(outer.peer)) return;

  const inner = decodeClientMessage(outer.ct);
  if (!inner) return;

  if (inner.type === "pair_request") {
    await this.handlePairRequest(input.relay, outer.peer, inner);
    return;
  }

  const known = await this.deps.findKnownPeer(outer.peer);
  if (!input.isCurrent()) return;
  if (known) {
    const channel = this.attach({ peerId: outer.peer, peerName: known.name, roomId: input.roomId, turnActive: input.turnActive() });
    this.routeFrom(channel, inner);
    return;
  }

  input.sendToPeer(outer.peer, { type: "error", code: "unknown_peer", message: "Peer not paired — re-scan QR" });
}
```

## Implementation Notes

- Keep `peers.json` semantics unchanged: multiple Owner records are allowed, `addPeer()` remains idempotent by `remote_epk`, and list/remove behavior remains in `pairing/storage.ts`.
- Preserve pair-request token behavior exactly: expired/consumed/unknown map to the same `pair_error` codes/messages; successful pairing sends one sender-specific `pair_ok` and attaches the owner.
- Preserve reconnect behavior: a known owner that sends any non-pair message while no channel is active gets attached and the first consumed inner is routed exactly once.
- Preserve unknown-peer behavior: pair requests from unknown peers are legitimate; non-pair messages from unknown peers get a sender-only `error{unknown_peer}` without logging payload contents.
- Use `unknown` + narrow helpers for outer/inner decode inside the owner boundary. Do not broaden runtime acceptance or change protocol validation semantics.
- Keep `session_id` opaque: pair_ok/session routing may carry it, but the owner multiplexer compares owner peer ids and room identity only.

## Acceptance Criteria

- [ ] Auto-listener pairing/reconnect/unknown-peer decisions live behind the owner multiplexer.
- [ ] Pairing a second Owner while one Owner is already attached succeeds and does not disconnect the first.
- [ ] Re-pairing the same Owner remains idempotent and avoids leaked channel listeners.
- [ ] Pair request responses remain sender-specific and use the same wire shape, including opaque `session_id` when present.
- [ ] Existing pair_request, unknown_peer, reconnect race, and multi-owner pairing tests pass.
- [ ] `corepack pnpm test -- src/extension.test.ts -t "pair_request|unknown peer|multi-channel broadcast|shutdown"` and `corepack pnpm typecheck` pass.

## Risk

High. This is the ingress decision point; mistakes can either reject valid reconnects, consume pair tokens incorrectly, or route one owner's first message twice.

## Rollback

Move `_installAutoListener`, `_findKnownPeer`, and `_handlePairRequest` bodies back into `index.ts` and have the relay transport install the legacy listener directly.
