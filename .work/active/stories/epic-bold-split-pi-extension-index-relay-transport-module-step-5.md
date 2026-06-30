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

## Risk
High. Owner ingress and relay reconnect share the same message stream; duplicate
listeners can double-deliver app messages, while missing listeners can strand
paired apps after reconnect.

## Rollback
Restore direct `_installAutoListener(relay)` and `new PlainPeerChannel(relay, ...)`
construction in `index.ts`. Because the wire format is unchanged, rollback is a
wiring-only revert.

## Implementation
- Duplicate-listener fix: `RelayTransportPort.onOuterMessage()` now only records outer-message handlers; relay socket attachment is owned by `bindRelay()` so a connected relay has exactly one owner-ingress `message` listener before peer attach.
- Owner ingress routing: `index.ts` installs one owner-ingress subscription through relay transport, keeps it across relay reconnect, and creates owner/transient peer channels through `RelayTransportAdapter.createPeerChannel()` instead of constructing `PlainPeerChannel` directly.
- No-double-deliver/no-strand guards: known-peer first non-pair messages are routed once after channel attach; relay close detaches owner channels while retaining owner ingress for the next bound relay; stop/unsubscribe removes the transport handler.
- Compatibility locked: added owner-ingress invariant tests for known-peer first-message single delivery and relay reconnect detach/reattach.
- Verification: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; targeted vitest `known peer reconnect|relay reconnect detaches` passed 2/2. Full `vitest run src/extension.test.ts src/transport/relay_client.test.ts` had 157 passed / 4 failed; the 4 failures match the documented false-alarm environment pattern (`after a clean reset`, `name-assigned`, `rename:<name>`, same-name cwd-lock), while the two owner-ingress invariant tests passed.
- Discrepancies from design: `createPeerChannel` is exposed on the concrete relay transport adapter with an optional composition-root port method to avoid modifying `legacy_ports.ts`; a single temporary current-relay epoch check remains for legacy owner ingress until the pairing coordinator is retired.
- Adjacent issues parked: none.
