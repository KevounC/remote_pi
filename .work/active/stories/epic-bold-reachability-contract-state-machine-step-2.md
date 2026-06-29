---
id: epic-bold-reachability-contract-state-machine-step-2
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-reachability-contract-state-machine
depends_on: [epic-bold-reachability-contract-state-machine-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Add the TypeScript Reachability projection module

**Priority**: High
**Risk**: Low
**Source Lens**: missing abstraction / single-source-of-truth drift
**Files**: `pi-extension/src/reachability/contract.ts`, `pi-extension/src/reachability/contract.test.ts`

## Current State

The extension has two independent reconnect/backoff encodings and a separate relay status union:

```ts
// pi-extension/src/index.ts
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
let _reconnectTimer: ReturnType<typeof setTimeout> | null = null;
let _reconnectAttempt = 0;
```

```ts
// pi-extension/src/session/mesh_node.ts
private relayReconnectTimer: ReturnType<typeof setTimeout> | null = null;
private relayBackoffIdx = 0;
private static readonly RELAY_RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
```

## Target State

Add a pure TS projection of the contract without yet rewiring adapters:

```ts
// pi-extension/src/reachability/contract.ts
export const REACHABILITY_STATES = [
  "connecting",
  "online",
  "degraded",
  "offline",
  "retrying",
] as const;

export type ReachabilityState = (typeof REACHABILITY_STATES)[number];

export const REACHABILITY_DISPLAY_NAMES: Record<ReachabilityState, string> = {
  connecting: "Connecting",
  online: "Online",
  degraded: "Degraded",
  offline: "Offline",
  retrying: "Retrying",
};

export const REACHABILITY_BACKOFF_MS = [1_000, 2_000, 5_000, 10_000, 30_000] as const;

export function reachabilityBackoffMs(attempt: number): number {
  const safeAttempt = Number.isFinite(attempt) ? Math.max(0, Math.trunc(attempt)) : 0;
  return REACHABILITY_BACKOFF_MS[Math.min(safeAttempt, REACHABILITY_BACKOFF_MS.length - 1)]!;
}

export const REACHABILITY_HEARTBEAT = {
  appProtocolPingMs: 25_000,
  relayWsPingMs: 25_000,
  extensionLivenessCheckMs: 20_000,
  extensionLivenessTimeoutMs: 70_000,
  degradedAfterMissedAppPongs: 3,
} as const;

export const REACHABILITY_TRANSITIONS = [
  ["offline", "connect_requested", "connecting"],
  ["connecting", "connect_succeeded", "online"],
  ["connecting", "connect_failed_retryable", "retrying"],
  ["connecting", "connect_cancelled", "offline"],
  ["online", "app_protocol_silence", "degraded"],
  ["online", "transport_closed", "retrying"],
  ["online", "stop_requested", "offline"],
  ["degraded", "fresh_app_frame_or_room_snapshot", "online"],
  ["degraded", "transport_closed", "retrying"],
  ["degraded", "stop_requested", "offline"],
  ["retrying", "retry_timer_fired", "connecting"],
  ["retrying", "stop_requested", "offline"],
  ["retrying", "retry_disabled", "offline"],
] as const satisfies readonly (readonly [ReachabilityState, string, ReachabilityState])[];
```

## Implementation Notes

- Keep the module pure: no WebSocket, Pi SDK, filesystem, timers, or relay imports.
- Tests should import the JSON artifact from `.orchestration/contracts/reachability.json` using `fs.readFileSync` and assert states, display names, backoff seconds, heartbeat timings, and transition triples match the TS projection.
- Do not replace `index.ts` or `mesh_node.ts` constants here; `epic-bold-reachability-contract-pi-adapter` owns mechanical adoption.
- ESM imports in tests must include `.js` for source imports.

## Acceptance Criteria

- [ ] `corepack pnpm test -- reachability` (or the nearest Vitest filter) passes from `pi-extension/`.
- [ ] The TS state union is derived from `REACHABILITY_STATES`.
- [ ] `reachabilityBackoffMs()` clamps attempts to `[1s, 2s, 5s, 10s, 30s, 30s, ...]`.
- [ ] TS tests fail if the interim JSON contract states/backoffs/heartbeat/transitions drift.
- [ ] No production reconnect behavior changes in this story.

## Risk

Low. This introduces a pure module and tests only. The only likely failure mode is a brittle relative path from the test to the repo-level contract artifact.

## Rollback

Delete `pi-extension/src/reachability/contract.ts` and its test. Existing reconnect code remains unchanged.
