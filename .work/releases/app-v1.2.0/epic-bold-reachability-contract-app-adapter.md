---
id: epic-bold-reachability-contract-app-adapter
kind: feature
stage: done
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract
depends_on: [epic-bold-reachability-contract-state-machine]
release_binding: app-v1.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Reachability — app ConnectionManager adapter

## Brief
`ConnectionManager` becomes an adapter over the canonical `Reachability` contract.
Its private backoff/timer state (`_retryAttempt`, `_missedPings`, `_connectInFlight`,
`_retryTimer`, `_pingTimer`) is moved into a dedicated reachability runtime
while preserving the existing public `ConnectionStatus` surface and outward reconnect
cadence. This keeps user-visible behavior stable while unifying app reachability
logic with `protocol/schema/reachability.json`.

## Epic context
- Parent epic: `epic-bold-reachability-contract`
- Position: consumer of `reachability-state-machine`.

## Foundation references
- Evidence: `app/lib/data/transport/connection_manager.dart:70-155`,
  `:556-785`, `:1041-1180`.

## Current State

The `app` transport owns reachability transitions in `ConnectionManager` itself via
private flags and timers:

```dart
int _missedPings = 0;
int _retryAttempt = 0;
bool _connectInFlight = false;
Timer? _retryTimer;
Timer? _pingTimer;
```

Retry spacing and heartbeat constants are also duplicated locally (`_kBackoff` and
`Timer.periodic(const Duration(seconds: 25))`), and `StatusOffline`/`StatusRetrying`
are emitted from the same methods that mutate these fields.

The cleanest explicit status model (`StatusNoPeer`, `StatusConnecting`, `StatusOnline`,
`StatusRetrying`, `StatusOffline`) remains correct and stable and is therefore
valuable to preserve during migration.

## Target State

`ConnectionManager` becomes an adapter/driver over a dedicated app-side reachability
runtime that is sourced from `app/lib/domain/value_objects/reachability.dart` (and
`reachability.json` through that sibling story's tests):

- Canonical states become the source of truth: `Connecting / Online / Degraded /
  Offline / Retrying`.
- Retry delays come from the contract backoff sequence `[1, 2, 5, 10, 30]` seconds.
- Heartbeat/degrade policy remains app cadence: `25/25/20/70` with degraded
after 3 missed app-layer pongs.
- `ConnectionStatus` is still emitted so call-sites (`main.dart`, `home/chat
  viewmodels`, `sync_service`, `actions_repository`) stay behavior-stable.
- Public behavior (no peer/connecting/reconnecting/online transitions, room liveness
decay to offline, in-flight connect shielding, watchdog recovery, retry loop
shape) remains unchanged.

## Design notes

- This is an adapter refactor, not protocol redesign. No wire shape, endpoint,
or timer-frequency behavior change is introduced.
- `reachability.dart` is kept in `domain/value_objects` and remains pure;
  `ConnectionManager` owns timers and sockets.
- `_connectInFlight` is moved into the adapter's lifecycle context so the
  watchdog can query intent from reachability state instead of raw `ConnectionManager`
  booleans.
- `Degraded` is represented internally; externally, room liveness (`isRoomLive`)
is still driven by the existing room cache with `_markActiveRoomOffline()` to avoid
introducing a new public degraded connection status while the UI contract remains
in use.
- `ConnectionStatus` keeps `attempt` on `StatusRetrying` and `canRetry` on
`StatusOffline` to preserve downstream tests and UI assumptions.
- Keep the branch migration-friendly: no assumptions in this refactor are written
that couple the app adapter to fork-only schema evolution.

## Refactor Overview

The refactor is decomposed into three implementation passes:

1. Introduce a pure reachability runtime/adapter object sourced from the
   canonical contract constants.
2. Replace direct state mutation in `ConnectionManager` with adapter transitions
   while preserving current status/event outputs.
3. Add/expand transport + domain tests that assert backward-compatible behavior
   against the same events/retry ladder.

Manual cycle check (no `work-view` available in this shell):
- Feature depends on `epic-bold-reachability-contract-state-machine`.
- Step dependencies are chained `step-1 → step-2 → step-3`.
- No downstream item currently depends back on this feature or its stories.

## Refactor Steps

### Step 1: Add app reachability adapter runtime over the contract
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / single source of truth
**Files**: `app/lib/data/transport/reachability_adapter.dart`, `app/lib/domain/value_objects/reachability.dart`
**Story**: `epic-bold-reachability-contract-app-adapter-step-1`

**Current State**:

```dart
// app/lib/data/transport/connection_manager.dart
int _missedPings = 0;
int _retryAttempt = 0;
bool _connectInFlight = false;

Duration _backoffFor(int attempt) =>
    Duration(seconds: _kBackoff[attempt.clamp(0, _kBackoff.length - 1)]);
```

```dart
const _kBackoff = [1, 2, 5, 10, 30];
```

**Target State**:

```dart
// app/lib/data/transport/reachability_adapter.dart
import 'package:app/domain/value_objects/reachability.dart';

final class ReachabilityAdapter {
  var state = ReachabilityState.offline;
  var retryAttempt = 0;
  var missedPings = 0;
  var connectInFlight = false;

  Duration get nextRetryDelay => reachabilityBackoffForAttempt(retryAttempt);
  bool get waitingForRetry => state == ReachabilityState.retrying;

  void onConnectRequested() { state = ReachabilityState.connecting; connectInFlight = true; }
  void onConnectSucceeded() { state = ReachabilityState.online; retryAttempt = 0; missedPings = 0; connectInFlight = false; }
  void onConnectFailedRetryable() { state = ReachabilityState.retrying; retryAttempt += 1; connectInFlight = false; }
  void onTransportClosed() { state = ReachabilityState.retrying; missedPings = 0; }
  void onAppTraffic() { retryAttempt = 0; missedPings = 0; state = ReachabilityState.online; }
  void onPingMissed() { missedPings++; if (missedPings >= reachabilityHeartbeat.degradedAfterMissedAppPongs) state = ReachabilityState.degraded; }
  void onStopRequested() { state = ReachabilityState.offline; connectInFlight = false; }
  void reset() { state = ReachabilityState.offline; retryAttempt = 0; missedPings = 0; connectInFlight = false; }
}
```

**Implementation Notes**:

- Keep this file transport-agnostic: no `IChannel`, no `WebSocket`, no UI, no
  persistence.
- Preserve the existing `ReachabilityState.degraded` as app/local degradation,
  not relay-level disconnect.
- Use contract heartbeat values and backoff from `reachability.dart` (which is
  validated against `protocol/schema/reachability.json`).
- Keep naming close to current `ConnectionManager` events to minimize migration
  risk (`connectRequested`, `connectSucceeded`, `appFrameObserved`,
  `transportClosed`, `pingMissed`, `retryTimerFired`).

**Acceptance Criteria**:

- [ ] New adapter compiles without `data/transport` imports.
- [ ] All transition outputs map 1:1 to existing `ConnectionStatus` cases.
- [ ] Backoff and heartbeat values are sourced from the contract helpers.
- [ ] Unit test file validates `_kBackoff`-equivalent progression and degraded-after
  threshold from contract constants.

**Risk**

Medium. Adapter boundary design can over-abstract or under-model edge transitions
(such as stop/connect cancellation ordering), creating subtle reconnect regressions.

**Rollback**

Remove the adapter file and keep all connection logic in `ConnectionManager`.

---

### Step 2: Drive `ConnectionManager` from the reachability adapter
**Priority**: High
**Risk**: Medium
**Source Lens**: lifecycle convergence / behavior-preserving adapter extraction
**Files**: `app/lib/data/transport/connection_manager.dart`
**Story**: `epic-bold-reachability-contract-app-adapter-step-2`

**Current State**:

```dart
void _connect(PeerRecord peer) async {
  _cancelRetry();
  _cancelPing();
  _connectCancel?.cancel();
  _connectInFlight = true;
  _activePeer = peer;
  _emit(const StatusConnecting());
  try {
    final ch = await _factory(peer, token);
    _missedPings = 0;
    _emit(StatusOnline(ch));
    _startPing(peer, ch);
    ...
  } catch (_) {
    if (!token.isCancelled) _scheduleRetry(peer);
  } finally {
    if (identical(_connectCancel, token)) _connectInFlight = false;
  }
}
```

**Target State**:

`ConnectionManager` owns no reachability flags/timers, only lifecycle side effects
and public status mapping:

- Adapter holds state progression and counters.
- `_watchdogTimer`, ping scheduling, channel close handling all call adapter
  methods before deciding on side effects.
- `_status` emission is derived from adapter transitions, preserving emitted
  `StatusConnecting`, `StatusOnline`, `StatusRetrying`, and `StatusOffline` shapes.
- `_startPing` keeps periodic cadence and unchanged behavior (`3` misses marks
  active room offline), but miss bookkeeping is delegated to the adapter.

**Implementation Notes**:

- Replace `_retryAttempt`, `_missedPings`, `_connectInFlight`, `_watchdog` state
  checks with `ReachabilityAdapter` queries.
- Keep `StatusNoPeer` as the explicit UX no-peer terminal state unchanged.
- Keep `_teardownActive`, `disconnect()`, `switchTo()`, and stale `onDone` guards.
- Keep all cadence constants and stream types intact (`Retrying` still exposes
  `nextRetry` and `attempt`, `StatusOffline` still exposes `canRetry`).
- Do not change RoomInfo cache semantics (`isRoomLive`/`isRoomWorking`) in this
  story.

**Acceptance Criteria**:

- [ ] Existing transport tests continue to pass (`connection_manager_test.dart`,
  `connection_manager_working_test.dart`, `connection_manager_thinking_test.dart`).
- [ ] `_retryAttempt`, `_missedPings`, and `_connectInFlight` no longer exist on
  `ConnectionManager`.
- [ ] Retry ladder still emits `attempt=0,1,...` as before on repeated connect
  failures.
- [ ] `app/lib/data/transport/connection_manager.dart` imports `reachability.dart`
  only through a pure adapter boundary.

**Risk**

Medium. This step replaces core lifecycle mutation points and could introduce
reconnect race conditions if event ordering is wrong (especially in-flight
connect, stale `onDone`, and watchdog paths).

**Rollback**

Revert `ConnectionManager` transition refactor to direct local fields; keep the
adapter file in place only if step3 is still usable independently.

---

### Step 3: Preserve compatibility with adapter-level behavior tests
**Priority**: High
**Risk**: Medium
**Source Lens**: testing integrity / lifecycle convergence
**Files**: `app/lib/data/transport/reachability_adapter.dart`, `app/test/domain/reachability_test.dart`, `app/test/transport/connection_manager_test.dart`
**Story**: `epic-bold-reachability-contract-app-adapter-step-3`

**Current State**:

No dedicated adapter tests exist for app transport reachability semantics, while
transport tests mainly assert public status transitions indirectly.

**Target State**:

- Add unit tests over the adapter for transitions and event ordering
  (`connectRequested`→`connecting`→`retrying`→`connecting` etc.).
- Add or extend transport tests that assert unchanged status stream behavior under
  failure, adopt/switch/no-peer edge paths.
- Keep drift checks in the existing value-object test path so backoff/heartbeat
  remain tied to `reachability.json`.

**Implementation Notes**:

- Reuse deterministic tests from sibling stories for contract drift.
- Add one explicit test that proves `missedPings` counter and degraded threshold
  semantics remain behavior-equivalent to existing code.
- Keep async expectations bounded and deterministic (avoid fragile fixed waits > 25s by
  testing adapter state transitions directly).

**Acceptance Criteria**:

- [ ] `flutter test test/domain/reachability_test.dart` passes.
- [ ] `flutter test test/transport/connection_manager_test.dart` passes.
- [ ] Adapter tests enforce the 3-miss degraded path and clamp-safe backoff indexing.

**Risk**

Medium. Overly strict private-state tests can become brittle and block future
`patchbay`-driven model migrations if they couple to internal implementation
choices.

**Rollback**

Revert test additions/adjustments and keep previous behavior-assertion coverage in
`connection_manager_test.dart`.

## Implementation Order

1. `epic-bold-reachability-contract-app-adapter-step-1` — introduce reachability adapter
2. `epic-bold-reachability-contract-app-adapter-step-2` — refactor `ConnectionManager`
3. `epic-bold-reachability-contract-app-adapter-step-3` — add/extend compatibility tests

## Risks and Rollback Summary

- Main risk is hidden ordering regressions in reconnect edge cases around stale
  channels, canceled connects, and watchdog recovery.
- This is an adapter-only refactor; all user-visible statuses, backoff timings,
and heartbeat intervals must stay unchanged.
- If regressions surface, rollback in order: step3 tests, then step2 wiring,
and finally step1 adapter introduction.