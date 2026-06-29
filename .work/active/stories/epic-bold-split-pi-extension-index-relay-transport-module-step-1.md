---
id: epic-bold-split-pi-extension-index-relay-transport-module-step-1
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-split-pi-extension-index-relay-transport-module
depends_on: [epic-bold-split-pi-extension-index-composition-root, epic-bold-reachability-contract-pi-adapter-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Introduce the RelayTransportPort adapter module shell

## Current State
Relay transport state is owned by `pi-extension/src/index.ts` globals, while the
low-level WebSocket client lives separately:

```ts
let _relay: RelayClient | null = null;
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";
let _lastRelayStatus: RelayConnectivity | null = null;
let _relayUrl: string | null = null;
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
let _reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let _reconnectAttempt = 0;
```

`transport/relay_client.ts` owns auth and liveness, but not reconnect/status or
room-meta lifecycle.

## Target State
Create a named adapter module that implements the composition-root
`RelayTransportPort` without moving all call sites yet:

```ts
// pi-extension/src/extension/relay_transport.ts
export interface RelayTransportDeps {
  createRelay(url: string, keypair: Ed25519Keypair): RelayClient;
  toWebSocketUrl(url: string): string;
  backoffMs(attempt: number): number;
  now(): number;
  setTimer(cb: () => void, delayMs: number): ReturnType<typeof setTimeout>;
  clearTimer(timer: ReturnType<typeof setTimeout>): void;
}

export function createRelayTransportPort(deps: RelayTransportDeps): RelayTransportPort {
  let relay: RelayClient | null = null;
  let relayUrl: string | null = null;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let reconnectAttempt = 0;
  let lastStatus: RelayConnectivity | null = null;
  // start/stop/status/sendRoomMeta/onOuterMessage/attachCrossPcBridge implemented here.
}
```

The module imports the reachability projection from
`pi-extension/src/reachability/reachability_contract.ts` for backoff/liveness
values; this story depends on the reachability pi-adapter liveness step so the
same constants are not duplicated.

## Notes
- Keep the shell side-effect free except for methods invoked by callers.
- Preserve ESM `.js` imports and strict TypeScript.
- Do not change protocol frames, CLI output, relay auth, or reconnect timing.
- The shell may temporarily expose a legacy `currentRelayForOwnerChannels()` or
  equivalent escape hatch only to bridge existing owner code; mark it internal
  and remove it in a later owner-multiplexer extraction.

## Acceptance Criteria
- [ ] A relay transport adapter module exists under `pi-extension/src/extension/` (or a similarly named extension-runtime boundary).
- [ ] The adapter implements the `RelayTransportPort` contract from the composition-root feature.
- [ ] The adapter owns private relay/reconnect/status fields instead of adding new `index.ts` globals.
- [ ] Reachability timing imports come from the reachability projection; no new duplicated backoff ladder is introduced.
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.

## Risk
Medium. This is mostly type/module setup, but it establishes the seam every later
step depends on.

## Rollback
Delete the new adapter module and its type-only imports. No runtime behavior
should have changed in this step.
