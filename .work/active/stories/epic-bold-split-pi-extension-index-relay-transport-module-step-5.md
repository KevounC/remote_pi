---
id: epic-bold-split-pi-extension-index-relay-transport-module-step-5
kind: story
stage: review
tags: [refactor]
parent: epic-bold-split-pi-extension-index-relay-transport-module
depends_on: [epic-bold-split-pi-extension-index-relay-transport-module-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 5: Route owner ingress through RelayTransportPort and lock compatibility tests

## Current State
`index.ts` installs the relay auto-listener and owner-specific channels against a
concrete `RelayClient`:

```ts
_stopAutoListener = _installAutoListener(relay);

function _installAutoListener(relay: RelayClient): () => void {
  const onMsg = async (line: string) => { /* pair_request / known-peer attach */ };
  relay.on("message", onMsg);
  return () => relay.off("message", onMsg);
}

const channel = new PlainPeerChannel(
  relay,
  appPeerId,
  _myRoomId ?? undefined,
  (msg) => _routeClientMessageFrom(channel, msg, _lastEventCtx ?? _lastCtx ?? _noopCtx),
  () => _onPeerDisconnect(appPeerId),
);
```

This keeps owner ingress coupled to relay socket ownership even after the relay
lifecycle moves to the transport module.

## Target State
Owner ingress subscribes through the port and uses a narrow channel factory
rather than reaching into relay globals:

```ts
const unsubscribe = ports.relay.onOuterMessage((line) => {
  void legacyOwnerIngress.handleOuterLine(line);
});

const channel = ports.relay.createPeerChannel({
  peerId: appPeerId,
  roomId: currentRoomId,
  onMessage: (msg) => owners.routeFrom(channel, msg),
  onDisconnect: () => owners.detach(appPeerId, "session_replaced"),
});
```

If the composition-root port surface does not include `createPeerChannel`, keep a
single temporary legacy escape hatch in the owner adapter and document that the
owner-multiplexer feature removes it. The relay transport remains the owner of
`RelayClient` and the only module with direct `relay.on("message")` /
`relay.off("message")` access.

## Notes
- Preserve the known-peer reconnect path exactly: first non-pair message from a known peer attaches and routes the consumed inner message once.
- Preserve unknown-peer error behavior and do not log message payloads.
- Preserve test-only exports (`_hasPendingReconnect`, `routeClientMessage`, `_routeClientMessageFrom`) as compatibility shims until the composition-root/test-harness stories retire them.
- Do not change `PlainPeerChannel` wire format; this is a wiring refactor only.

## Acceptance Criteria
- [ ] `index.ts` no longer installs relay message listeners directly except through `RelayTransportPort.onOuterMessage()` or a named temporary legacy adapter.
- [ ] Owner pair, known-peer reconnect, unknown-peer error, multi-owner fanout, and session_sync tests still pass.
- [ ] `PlainPeerChannel`, `PiForwardClient`, and `RelayClient` remain behavior-compatible; no public exports are removed.
- [ ] A relay-transport-focused test or existing `extension.test.ts` assertions prove reconnect still detaches owners and lets known peers reattach.
- [ ] `corepack pnpm test -- src/extension.test.ts src/transport/relay_client.test.ts` and `corepack pnpm typecheck` pass.

## Implementation
- Routed owner ingress through the relay transport outer-message subscription and moved owner channel construction behind `RelayTransportAdapter.createPeerChannel()`, so `index.ts` no longer constructs `PlainPeerChannel` or installs relay message listeners directly.
- Made `attachCrossPcBridge()` idempotent at the relay-transport boundary: repeated calls for the same relay, mesh node, relay URL, and Pi key await the in-flight/current attach instead of constructing duplicate `PiForwardClient` listeners; changed bridge inputs still detach and reattach.
- Kept the three existing bridge call paths safe by deduping at the ownership seam rather than changing cross-PC wire adapters.
- Re-added the two invariant tests for known-peer reconnect and relay reconnect reattach. The targeted run passed with 2 tests passed, 0 failed; the first invariant proves listener count is exactly 1 after connect and exactly 2 after known-peer channel attach.
- Full `extension.test.ts` + `transport/relay_client.test.ts` still shows only the pre-briefed false-alarm failures (`after a clean reset`, `name-assigned`, `rename:<name>`, cwd-lock same-name); no listener-count, route-count, detach, reattach, message, or pong-count failures occurred.

## Risk
High. Owner ingress and relay reconnect share the same message stream; duplicate
listeners can double-deliver app messages, while missing listeners can strand
paired apps after reconnect.

## Rollback
Restore direct `_installAutoListener(relay)` and `new PlainPeerChannel(relay, ...)`
construction in `index.ts`. Because the wire format is unchanged, rollback is a
wiring-only revert.
