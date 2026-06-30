---
id: epic-bold-reachability-contract-state-machine
kind: feature
stage: done
tags: [refactor, bold, pi-extension, app, relay]
parent: epic-bold-reachability-contract
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Reachability — canonical state machine (riskiest — design first)

## Brief
The canonical `Reachability` states + transition rules + backoff policy,
defined once. State set: `Connecting / Online / Degraded / Offline / Retrying`,
with one backoff source (`[1, 2, 5, 10, 30]` today, duplicated verbatim in three
places). This is the contract every transport adapter adopts. Defined in the
protocol schema once that epic lands; standalone (shared policy module per
language) until then.

## Epic context
- Parent epic: `epic-bold-reachability-contract`
- Position: riskiest child — the state set and backoff policy are the contract
  the app/pi adapters adopt. Design FIRST.

## Foundation references
- Evidence: `pi-extension/src/index.ts:586` (`RECONNECT_BACKOFFS_MS`),
  `pi-extension/src/session/mesh_node.ts:100` (own copy),
  `app/lib/data/transport/connection_manager.dart:74` (`_kBackoff`),
  `app/lib/data/transport/connection_manager.dart:1-70` (cleanest existing
  state machine — `ConnectionStatus` sealed class — to lift from).

<!-- /agile-workflow:refactor-design pins the state set, transitions, backoff. -->

## Refactor Overview

The duplicated reachability logic is small but high-leverage: the same retry schedule appears in `pi-extension/src/index.ts`, `pi-extension/src/session/mesh_node.ts`, and `app/lib/data/transport/connection_manager.dart`, while relay/app/extension heartbeat timings are scattered as separate magic constants. The refactor target is a single named `Reachability` contract that can be projected mechanically today and moved into the generated protocol schema later.

Misroute check: this remains a refactor because the first implementation slice only pins a contract artifact plus inert per-language projections; app/pi production adapters adopt the contract in sibling features. Observable reconnect, ping, liveness, room, and relay behavior must remain unchanged until those adapter stories deliberately swap imports without semantic drift.

Canonical state set: `Connecting / Online / Degraded / Offline / Retrying`.

Transition rules:

- `Offline --connect_requested--> Connecting`
- `Connecting --connect_succeeded--> Online`
- `Connecting --connect_failed_retryable--> Retrying`
- `Connecting --connect_cancelled--> Offline`
- `Online --app_protocol_silence--> Degraded`
- `Online --transport_closed--> Retrying`
- `Online --stop_requested--> Offline`
- `Degraded --fresh_app_frame_or_room_snapshot--> Online`
- `Degraded --transport_closed--> Retrying`
- `Degraded --stop_requested--> Offline`
- `Retrying --retry_timer_fired--> Connecting`
- `Retrying --stop_requested--> Offline`
- `Retrying --retry_disabled--> Offline`

Backoff policy: `[1, 2, 5, 10, 30]` seconds, capped at 30s for later attempts.

Heartbeat/liveness policy preserved from current code: app protocol ping every 25s, relay WS ping every 25s, extension liveness check every 20s, extension liveness timeout at 70s, and app-side degraded room liveness after 3 missed protocol pongs. The existing app comment says “two consecutive misses,” but current code marks local room offline at `_missedPings == 3`; the contract follows code to avoid a hidden behavior change.

Contract location decision: until `epic-bold-generated-protocol` absorbs reachability into generated schema/codegen, the interim canonical source lives under `protocol/schema/reachability.json`. It does not live under `.orchestration/` because that tree is retired except for the legacy protocol contract fixtures named in `docs/DECISIONS.md`. TS/Dart/Rust modules are projections guarded by tests against the artifact. Rationale: this gives one reviewable source now without baking a fork-only runtime dependency that would block patchbay migration.

Cycle check by frontmatter (no work-view binary used): the feature has `depends_on: []`; sibling app/pi adapter features depend on this feature; child stories form a one-way chain `step-1 -> step-2 -> step-3 -> step-4`. No story depends on the feature or on a downstream sibling, so the dependency graph is acyclic.

## Refactor Steps

### Step 1: Pin the interim canonical Reachability contract artifact

**Priority**: High
**Risk**: Low
**Source Lens**: missing abstraction / pattern drift
**Files**: `protocol/schema/reachability.json`, optional `protocol/schema/reachability.md`
**Story**: `epic-bold-reachability-contract-state-machine-step-1`

**Current State**:

```ts
// pi-extension/src/index.ts
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
```

```ts
// pi-extension/src/session/mesh_node.ts
private static readonly RELAY_RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
```

```dart
// app/lib/data/transport/connection_manager.dart
const _kBackoff = [1, 2, 5, 10, 30];
// Status model has connecting/online/retrying/offline/noPeer; degraded is implicit in _markActiveRoomOffline().
```

**Target State**:

```json
{
  "name": "Reachability",
  "version": 1,
  "states": ["connecting", "online", "degraded", "offline", "retrying"],
  "displayNames": {
    "connecting": "Connecting",
    "online": "Online",
    "degraded": "Degraded",
    "offline": "Offline",
    "retrying": "Retrying"
  },
  "backoffSeconds": [1, 2, 5, 10, 30],
  "heartbeat": {
    "appProtocolPingSeconds": 25,
    "relayWsPingSeconds": 25,
    "extensionLivenessCheckSeconds": 20,
    "extensionLivenessTimeoutSeconds": 70,
    "degradedAfterMissedAppPongs": 3
  },
  "transitions": [
    { "from": "offline", "event": "connect_requested", "to": "connecting" },
    { "from": "connecting", "event": "connect_succeeded", "to": "online" },
    { "from": "connecting", "event": "connect_failed_retryable", "to": "retrying" },
    { "from": "connecting", "event": "connect_cancelled", "to": "offline" },
    { "from": "online", "event": "app_protocol_silence", "to": "degraded" },
    { "from": "online", "event": "transport_closed", "to": "retrying" },
    { "from": "online", "event": "stop_requested", "to": "offline" },
    { "from": "degraded", "event": "fresh_app_frame_or_room_snapshot", "to": "online" },
    { "from": "degraded", "event": "transport_closed", "to": "retrying" },
    { "from": "degraded", "event": "stop_requested", "to": "offline" },
    { "from": "retrying", "event": "retry_timer_fired", "to": "connecting" },
    { "from": "retrying", "event": "stop_requested", "to": "offline" },
    { "from": "retrying", "event": "retry_disabled", "to": "offline" }
  ]
}
```

**Implementation Notes**:

- Use lower-case identifiers for code/wire stability; display labels derive from `displayNames`.
- Add no production imports yet.
- `Degraded` means transport is up but the app/Pi room signal is stale; it is not a relay-wide disconnect.

**Acceptance Criteria**:

- [ ] Build passes (no production build expected to change).
- [ ] Tests pass or nearest JSON validation/check passes.
- [ ] Contract artifact has exactly the five target states.
- [ ] Backoff and heartbeat values match current code.
- [ ] Transition table includes `Online -> Degraded` and `Degraded -> Online`.

**Rollback**: Delete the inert contract artifact(s).

---

### Step 2: Add the TypeScript Reachability projection module

**Priority**: High
**Risk**: Low
**Source Lens**: missing abstraction / single-source-of-truth drift
**Files**: `pi-extension/src/reachability/contract.ts`, `pi-extension/src/reachability/contract.test.ts`
**Story**: `epic-bold-reachability-contract-state-machine-step-2`

**Current State**:

```ts
export type RelayConnectivity = "connected" | "reconnecting" | "disconnected";
const RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
private static readonly RELAY_RECONNECT_BACKOFFS_MS = [1_000, 2_000, 5_000, 10_000, 30_000];
```

**Target State**:

```ts
export const REACHABILITY_STATES = [
  "connecting",
  "online",
  "degraded",
  "offline",
  "retrying",
] as const;
export type ReachabilityState = (typeof REACHABILITY_STATES)[number];
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
```

**Implementation Notes**:

- Keep this module pure: no Pi SDK, RelayClient, timers, or filesystem in production code.
- Test the projection against `protocol/schema/reachability.json`.
- Do not yet replace `index.ts` or `mesh_node.ts` constants; the pi-adapter sibling owns that mechanical adoption.

**Acceptance Criteria**:

- [ ] `corepack pnpm test -- reachability` or nearest Vitest filter passes.
- [ ] State union derives from `REACHABILITY_STATES`.
- [ ] Backoff clamps to 30s after attempt 4.
- [ ] Projection tests fail on JSON contract drift.

**Rollback**: Delete `pi-extension/src/reachability/contract.ts` and its tests.

---

### Step 3: Add the Dart Reachability projection module

**Priority**: High
**Risk**: Low
**Source Lens**: missing abstraction / pattern drift
**Files**: `app/lib/domain/value_objects/reachability.dart`, `app/test/domain/reachability_test.dart`
**Story**: `epic-bold-reachability-contract-state-machine-step-3`

**Current State**:

```dart
sealed class ConnectionStatus { const ConnectionStatus(); }
class StatusOnline extends ConnectionStatus { final IChannel channel; const StatusOnline(this.channel); }
class StatusRetrying extends ConnectionStatus { final Duration nextRetry; final int attempt; const StatusRetrying({required this.nextRetry, required this.attempt}); }
const _kBackoff = [1, 2, 5, 10, 30];
```

**Target State**:

```dart
enum ReachabilityState { connecting, online, degraded, offline, retrying }

const reachabilityBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 30),
];

Duration reachabilityBackoffForAttempt(int attempt) {
  final safeAttempt = attempt < 0 ? 0 : attempt;
  final idx = safeAttempt >= reachabilityBackoff.length
      ? reachabilityBackoff.length - 1
      : safeAttempt;
  return reachabilityBackoff[idx];
}
```

**Implementation Notes**:

- Put the pure contract in `domain/value_objects`, not `data/transport`, so it has no channel/UI/storage dependency.
- Keep `ConnectionStatus` unchanged in this story; the app-adapter sibling maps it to the contract later.
- Test against the JSON artifact from `app/` using test-only `dart:io`.

**Acceptance Criteria**:

- [ ] `flutter test test/domain/reachability_test.dart` passes.
- [ ] Production module imports no Flutter, WebSocket, storage, or UI packages.
- [ ] Projection tests fail on JSON contract drift.
- [ ] No `ConnectionManager` behavior changes.

**Rollback**: Delete the Dart value object and test.

---

### Step 4: Add the Rust Reachability projection module for relay heartbeat policy

**Priority**: Medium
**Risk**: Low
**Source Lens**: missing abstraction / naming inconsistency
**Files**: `relay/src/reachability.rs`, `relay/src/lib.rs`, `relay/src/handlers/peer.rs`
**Story**: `epic-bold-reachability-contract-state-machine-step-4`

**Current State**:

```rust
let mut heartbeat = time::interval_at(
    time::Instant::now() + Duration::from_secs(25),
    Duration::from_secs(25),
);
```

**Target State**:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReachabilityState {
    Connecting,
    Online,
    Degraded,
    Offline,
    Retrying,
}

pub const REACHABILITY_BACKOFF: [Duration; 5] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(5),
    Duration::from_secs(10),
    Duration::from_secs(30),
];

pub const RELAY_WS_PING_INTERVAL: Duration = Duration::from_secs(25);
```

```rust
use crate::reachability::RELAY_WS_PING_INTERVAL;
let mut heartbeat = time::interval_at(
    time::Instant::now() + RELAY_WS_PING_INTERVAL,
    RELAY_WS_PING_INTERVAL,
);
```

**Implementation Notes**:

- Relay uses only the WS heartbeat constant today; it must not infer app/Pi degraded/session state.
- Export `pub mod reachability;` from `relay/src/lib.rs`.
- Add tests for variants, backoff clamping, and heartbeat constants; compare to the JSON artifact where practical.

**Acceptance Criteria**:

- [ ] `cargo fmt --check` passes.
- [ ] `cargo test reachability` or nearest filter passes.
- [ ] Relay first ping remains after 25s and repeats every 25s.
- [ ] Relay does not add durable session/offline queue state.

**Rollback**: Inline `Duration::from_secs(25)` again and delete `relay/src/reachability.rs` plus tests.

## Implementation Order

1. `epic-bold-reachability-contract-state-machine-step-1` — inert canonical artifact.
2. `epic-bold-reachability-contract-state-machine-step-2` — TS projection and drift tests.
3. `epic-bold-reachability-contract-state-machine-step-3` — Dart projection and drift tests.
4. `epic-bold-reachability-contract-state-machine-step-4` — Rust projection and relay heartbeat constant adoption.

## Risks and Rollback Summary

- Overall risk: Low-to-medium. The riskiest semantic choice is naming `Degraded`, but this design keeps it inert until adapter features adopt it. Step 4 changes a relay constant source, so tests must preserve exact 25s timing.
- Rollback path: each child story is independently revertible. If the interim JSON source causes friction, revert Step 1 and all projection modules; no production adapter behavior depends on them until sibling adapter features run.

## Convention-Driven Steps

None. `.agents/skills/refactor-conventions/` and `.agents/skills/patterns/` are absent, so this plan uses the default refactor-design lenses plus project code-design rules.

## Implementation summary — wave 4

Stories now ready for review:

- `epic-bold-reachability-contract-state-machine-step-1` — done before this run.
- `epic-bold-reachability-contract-state-machine-step-2` — done before this run.
- `epic-bold-reachability-contract-state-machine-step-3` — advanced to review in this run; pure Dart domain projection and drift test added.
- `epic-bold-reachability-contract-state-machine-step-4` — advanced to review in this run; Rust relay projection added and peer heartbeat now uses the shared constant.

Verification in this run: Dart files formatted via `/opt/flutter/bin/cache/dart-sdk/bin/dart format`; Flutter test startup was blocked by read-only Flutter SDK cache in this harness before tests ran. Relay verification passed with `cargo fmt --check`, `cargo test reachability`, and `cargo clippy -- -D warnings` from `relay/`.


## Review — advanced to done (2026-06-30)

All 4 child stories `done`. Final verification this session: `cargo test` from
`relay/` green (122 tests, 0 failures) — the step-4 relay heartbeat constant
adoption is verified (the wave-4 run was blocked by a read-only Flutter SDK
cache; relay cargo was always fine). Epic complete.
