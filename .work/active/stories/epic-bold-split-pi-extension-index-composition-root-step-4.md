---
id: epic-bold-split-pi-extension-index-composition-root-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-composition-root
depends_on: [epic-bold-split-pi-extension-index-composition-root-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Route hooks, commands, and app ingress through the ports

## Current State
Pi lifecycle hooks and `PlainPeerChannel` callbacks call god-file helpers directly:

```ts
pi.on("session_start", (_event, ctx) => {
  _lastEventCtx = ctx;
  if (_disposed) {
    _disposed = false;
    void _cmdRoot(ctx);
  }
});

pi.on("session_shutdown", async () => {
  _disposed = true;
  _lastCtx = null;
  _lastEventCtx = null;
  _messageApi = null;
  _pi = null;
  if (_meshNode) await _meshNode.close();
  if (_state !== "idle") _goIdle();
});

const channel = new PlainPeerChannel(
  relay,
  appPeerId,
  _myRoomId ?? undefined,
  (msg) => _routeClientMessageFrom(channel, msg, _lastEventCtx ?? _lastCtx ?? _noopCtx),
  () => _onPeerDisconnect(appPeerId),
);
```

## Target State
Hook registration lives in `composition_root.ts` and delegates by port:

```ts
function registerLifecycleHooks(pi: ExtensionAPI, ports: RemotePiRuntimePorts, epoch: RuntimeEpoch): void {
  pi.on("session_start", (_event, ctx) => {
    ports.session.bindSessionContext(ctx);
    if (!epoch.isCurrent()) return;
    ports.commands.ensureStarted?.(ctx);
  });

  pi.on("session_shutdown", async () => {
    epoch.dispose();
    ports.session.clearStaleContexts();
    ports.relay.detachCrossPcBridge();
    ports.relay.stop();
    await ports.commands.closeMesh?.();
  });
}
```

Owner/app inbound messages enter through the owner/session ports, not through scattered free callbacks.

## Implementation Notes
- Keep `PlainPeerChannel` encoding/decoding and relay listener semantics unchanged.
- Preserve stale-context protection: actions prefer fresh `session_start` / `withSession` context over stale command context.
- Preserve late-attach protection: after awaits in relay connect, mesh join, bridge attach, and session replacement callbacks, check epoch/disposed before installing listeners or publishing state.
- If a route change would alter public behavior, leave it out and file behavior-changing follow-up instead.

## Acceptance Criteria
- [ ] Pi hook registration flows through `composition_root.ts`.
- [ ] Command registration flows through `CommandSurfacePort`.
- [ ] Owner/app inbound messages flow through `OwnerMultiplexerPort.routeFrom` / `SdkSessionProjectionPort.handleClientMessage`.
- [ ] Tests cover stale context after app-triggered `session_new` and late relay/bridge teardown guards.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test -- src/extension.test.ts` pass.

## Risk
High: this is the main wiring change and can break lifecycle ordering.

## Rollback
Restore direct hook/command registration and direct channel callbacks in `index.ts`; keep earlier type definitions if harmless.
