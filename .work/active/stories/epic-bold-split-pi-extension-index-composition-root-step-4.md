---
id: epic-bold-split-pi-extension-index-composition-root-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-composition-root
depends_on: [epic-bold-split-pi-extension-index-composition-root-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation
- Files changed: `pi-extension/src/extension/composition_root.ts`, `pi-extension/src/extension/ports.ts`, `pi-extension/src/extension/legacy_ports.ts`, `pi-extension/src/index.ts`, `pi-extension/src/extension/composition_root.test.ts`, `pi-extension/src/extension.test.ts`.
- Hook and command routing: `composition_root.ts` now exports `registerLifecycleHooks`; `session_start` binds fresh session context via `SdkSessionProjectionPort` and asks `CommandSurfacePort.ensureStarted` to rearm reused runtimes, while `session_shutdown` disposes the epoch before delegating stale-context clearing, bridge/relay teardown, mesh close, and cwd-lock release through ports. `index.ts` no longer registers `session_start` / `session_shutdown` inline; command registration remains through `CommandSurfacePort.register`.
- Owner/app ingress routing: pairing/known-owner ingress now enters `OwnerMultiplexerPort.routeFrom` and then `SdkSessionProjectionPort.handleClientMessage`; the only remaining direct `_routeClientMessageFrom` call is the legacy session-projection adapter boundary and test/backward-compat shims.
- Stale-context and late-attach preservation: the legacy command port preserves the existing `_disposed` latch before awaits; session start clears the latch only through `ensureStarted`, session shutdown clears stale Pi APIs before relay/mesh callbacks can touch them, and existing relay/known-peer/pair-request late continuation guards remain intact.
- Tests: `corepack pnpm typecheck` passed; `corepack pnpm build` passed; `corepack pnpm exec vitest run src/extension/composition_root.test.ts` passed (1 file, 4 tests); targeted lifecycle command `corepack pnpm exec vitest run src/extension.test.ts -t "session_start|session_shutdown|session_new|stale|late|relay|bridge|teardown"` reported 49 passed, 98 skipped, 2 failed matching the known false-alarm group (`after a clean reset...`, `rename:<name>...` / cwd-lock+UDS mesh). Full `corepack pnpm exec vitest run src/extension.test.ts` reported 145 passed, 4 failed, also matching the known false-alarm group (`after a clean reset`, `name-assigned`, `rename:<name>`, same-name `#N` / cwd-lock+UDS). Accidental `corepack pnpm test -- src/extension.test.ts` ran the broader suite and reported 585 passed, 3 skipped, 66 failed, all in the known sandbox UDS/cwd-lock/leader-election/supervisor.sock false-failure family.
- Discrepancies from design: added `CommandSurfacePort.prepareSessionShutdown` as a legacy compatibility hook so the existing `_disposed` guard is set before relay/mesh awaits; public behavior and wire semantics are unchanged.
- Adjacent issues parked: none.

## Review

Approved (2026-06-30) with HIGH-risk composition-root verification. Independently
re-ran: `corepack pnpm typecheck` clean; `corepack pnpm exec vitest run
src/extension/composition_root.test.ts` → 4/4; **full pi-ext suite 651 passed |
3 skipped | 0 failed (44 files)** — fully green (up from 649 — the agent's new
composition_root + lifecycle tests).

NOTE: the implementer CORRECTLY identified the false-failure pattern (5th
consecutive pi-ext agent to do so) — reported the targeted-lifecycle "2 failed"
and full-suite "4 failed" and broader "66 failed" as "all matching the known
false-alarm group (`after a clean reset`, `name-assigned`, `rename:<name>`,
`leader election`, `supervisor.sock`)". The orchestrator's independent vitest run
confirms 0 failures.

Commit `9dd6107` scoped to pi-ext only (composition_root.ts + ports.ts +
legacy_ports.ts + index.ts + tests); collision guard held. Lifecycle-ordering
verified: `registerLifecycleHooks` extracted; `session_start` binds fresh session
context via SdkSessionProjectionPort + rearms via CommandSurfacePort.ensureStarted;
`session_shutdown` disposes epoch FIRST, then clears stale contexts, detaches
bridge/stops relay, closes mesh, releases cwd-lock (the documented safe order);
owner/app ingress routes through OwnerMultiplexerPort.routeFrom →
SdkSessionProjectionPort.handleClientMessage (only the legacy session-projection
adapter boundary keeps direct `_routeClientMessageFrom`). Stale-context +
late-attach protection preserved (`_disposed` latch, epoch guard). The
`prepareSessionShutdown` port addition is a reasonable compat hook (behavior
unchanged).
