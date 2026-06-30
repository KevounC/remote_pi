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
- Routed owner ingress through `RelayTransportPort.onOuterMessage()` in `index.ts`; reconnect keeps the outer owner-ingress subscription owned by relay transport while relay-specific owner channels detach on drop.
- Added `RelayTransportPort.createPeerChannel()` in `relay_transport.ts` and moved owner `PlainPeerChannel` construction behind that port. `index.ts` no longer constructs `PlainPeerChannel` or installs relay message listeners directly.
- Preserved known-peer reconnect semantics: the first non-pair known-peer message attaches the owner and routes that consumed inner message exactly once; tests assert a single `pong` and listener counts before/after attach.
- Preserved unknown-peer behavior without logging payloads; one-off peer replies use the relay channel factory and detach immediately.
- Added reconnect coverage proving relay drop detaches owners, removes old message listeners, reconnect installs one owner-ingress listener, and the known peer reattaches/routes exactly once on the new relay stream.
- Verification:
  - `corepack pnpm typecheck` passed.
  - `corepack pnpm build` passed.
  - Focused owner-ingress vitest selection passed: 6 passed / 147 skipped in `src/extension.test.ts`.
  - Required combined vitest command reported 161 total tests: 157 passed / 4 failed. By file: `src/transport/relay_client.test.ts` 8 passed; `src/extension.test.ts` 149 passed / 4 failed. The 4 failures are the known false-alarm group (`after a clean reset`, `remote-pi:name-assigned`, `rename:<name>`, same-folder cwd-lock) described in the story prompt, not owner-ingress regressions.
