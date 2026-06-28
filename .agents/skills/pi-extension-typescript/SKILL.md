---
name: pi-extension-typescript
description: Remote Pi pi-extension TypeScript/Pi SDK reference. Read before editing or reviewing pi-extension/ code, session lifecycle hooks, relay/room metadata, mesh tools, pairing, or Pi SDK integration.
updated: 2026-06-27
---

# Pi Extension TypeScript Reference

> Local scope: `pi-extension/`
> Versions: Node >=20, TypeScript 6.x, `@earendil-works/pi-coding-agent` 0.79.x, `ws` 8.x, Vitest 4.x
> Canonical local docs: `pi-extension/CLAUDE.md`, `PROTOCOL.md`, Pi docs at `/home/agent/.local/lib/node_modules/@earendil-works/pi-coding-agent/docs/extensions.md`

## When to load

- Any edit or review under `pi-extension/`.
- Any change involving `/remote-pi`, session replacement (`/new`, `/resume`, `/fork`, `/reload`), mobile/client state, `room_meta`, mesh tools, pairing, relay connection, or broker/UDS behavior.
- Any investigation of stale context, stuck `Working`, dropped/replayed events, or multi-client state.

## Package commands

Run from `pi-extension/`:

```bash
corepack pnpm install   # if deps are missing
corepack pnpm typecheck # tsc --noEmit
corepack pnpm test      # vitest run
corepack pnpm build     # tsc -> dist/
```

Do not commit `dist/`, `node_modules/`, local `.pi/`, secrets, or generated build output.

## Module and TypeScript conventions

```ts
// ESM + NodeNext: relative imports include .js in TypeScript source.
import { RelayClient } from "./transport/relay_client.js";
import type { ClientMessage } from "./protocol/types.js";

// Prefer unknown + narrowing at boundaries.
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
```

- ESM only (`"type": "module"`); no `require`, `module.exports`, or CommonJS-only dependencies.
- Strict TypeScript; avoid `any` except at explicitly isolated test seams.
- Top-level await is allowed by ESM, but long-lived runtime work should be owned by lifecycle handlers and tear down on `session_shutdown`.
- Use named `Error` classes at boundaries; throw early when input/config is invalid.

## Pi SDK lifecycle quick reference

Pi extension lifecycle facts are load-bearing for Remote Pi:

```ts
pi.on("session_start", async (event, ctx) => {
  // reason: "startup" | "reload" | "new" | "resume" | "fork"
  // Re-establish session-scoped in-memory state here.
});

pi.on("session_shutdown", async (event, ctx) => {
  // reason: "quit" | "reload" | "new" | "resume" | "fork"
  // Tear down relay, mesh, sockets, timers, and stale ctx refs here.
});

pi.on("turn_start", async (event, ctx) => {
  // event.turnIndex, event.timestamp
});

pi.on("turn_end", async (event, ctx) => {
  // event.turnIndex, event.message, event.toolResults
});
```

Session replacement order from Pi docs:

```text
/new or /resume
  -> session_before_switch
  -> session_shutdown       # old extension instance/context
  -> session_start          # new session context
  -> resources_discover
```

`/fork` and `/clone` similarly emit `session_shutdown` then `session_start` with `reason: "fork"`. Treat all captured command/event contexts as session-scoped, not process-global.

## Remote Pi state boundaries

Important files:

- `src/index.ts` — extension factory, `/remote-pi` commands, relay + room metadata, session lifecycle hooks.
- `src/protocol/types.ts`, `src/protocol/codec.ts` — app/extension message shapes and validation.
- `src/transport/relay_client.ts`, `src/transport/peer_channel.ts` — relay WebSocket and per-peer channel routing.
- `src/session/*` — local UDS broker, mesh node, peer inventory, tools.
- `src/pairing/*` — QR/session token, key storage, peer records.
- `src/ui/footer.ts` — TUI footer rendering.
- `src/extension.test.ts` — high-value lifecycle regression coverage.

State ownership rules:

- The relay routes mobile/app traffic and room control messages; it is not an authority for Pi session internals.
- `room_meta` is the mobile app's hydration surface for room name, cwd, model, thinking, and `working` state.
- `_lastEventCtx`/current session context is the safe route for session actions after replacement; old command contexts can become stale.
- Mesh peers are agent endpoints (`<cwd>@<name>`), not human devices or UI clients.

## Lifecycle gotchas

### Stale context after session replacement

Recent bug class: callbacks captured an old Pi `ctx` and later used it after `/new`, `/resume`, reload, or reconnect. Pi marks old contexts stale; touching stale `ctx.ui`, `ctx.abort`, or similar can throw and crash or strand callbacks.

Rules:

- Re-capture fresh session context on every `session_start`.
- Clear or guard captured contexts on `session_shutdown`.
- Wrap UI/notify/footer paths so stale UI becomes a no-op, not a crash.
- Never route mobile-triggered actions through a command context captured before session replacement when a fresh event context is available.

### `working`/idle convergence

`room_meta.working` should be authoritative and convergent:

- publish `working: true` on `turn_start` and compaction-start paths;
- publish `working: false` on `turn_end`, compaction completion, abort/error cleanup, and session teardown/reconnect hydration where applicable;
- cache the latest room meta so reconnect hello carries current state;
- test dropped/replayed update scenarios and app hydration behavior before assuming the UI will self-correct.

The app may debounce or render transitions, but the extension must not leave durable room metadata stuck true after the agent is idle.

### Multi-client and mesh semantics

- Multiple mobile owners can attach to one Pi room; each owner has its own peer channel.
- Local/cross-PC mesh peers are coding-agent endpoints surfaced by agent-network tools.
- Do not infer human workstation/mobile presence from `list_peers`; it returns agent peers only.
- Cross-PC addresses include a `<pc>:` prefix and must be treated as opaque routing keys.

## WebSocket / relay client notes

- Use `ws` only in the extension; convert configured HTTP(S) relay URLs to WS(S) internally.
- Relay URL precedence: `REMOTE_PI_RELAY` env, `~/.pi/remote/config.json`, then default relay URL.
- Validate user-facing relay URLs; reject empty/malformed `ws://`/`wss://` in slash command input if the command expects HTTP(S).
- Reconnect code must rehydrate room metadata and bridge state without creating phantom rooms or ghost brokers.

## Pairing and key storage notes

- Pairing storage uses `@napi-rs/keyring` when available; headless Linux can fall back to `~/.pi/remote/identity.json` with `0600` permissions and a warning.
- Do not hand-roll crypto. Use existing helpers in `src/pairing/crypto.ts` and protocol helpers.
- Peer records and owner keys are machine/global state; update caches after add/remove and avoid stale in-memory assumptions.

## Anti-patterns

- Holding a module-level `ctx`/`ctx.ui` forever and using it after `/new`, `/resume`, or reload.
- Treating relay connection success as proof of current room/session state without sending fresh room meta.
- Publishing `working: true` without guaranteed false paths for turn end, errors, aborts, compaction, and shutdown.
- Logging payload contents or secrets while debugging relay/peer traffic.
- Mutating `_activePeers` or mesh/broker internals outside the helper paths that refresh footer/log/state.
- Adding broad dependencies without checking ESM compatibility and test impact.

## Review checklist

Before approving `pi-extension/` changes:

- [ ] Does every opened socket/timer/relay/mesh resource tear down on `session_shutdown`?
- [ ] Are all captured Pi contexts refreshed or guarded across session replacement?
- [ ] Does reconnect send an authoritative room snapshot, not just event deltas?
- [ ] Can `working` converge false after success, error, abort, compaction, and reconnect?
- [ ] Are multi-owner and mesh-peer semantics kept separate?
- [ ] Do tests cover the lifecycle or protocol edge touched by the change?
- [ ] Did `corepack pnpm typecheck`, `corepack pnpm test`, and `corepack pnpm build` pass?
