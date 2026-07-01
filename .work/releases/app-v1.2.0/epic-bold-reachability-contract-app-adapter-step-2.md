---
id: epic-bold-reachability-contract-app-adapter-step-2
kind: story
stage: done
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract-app-adapter
depends_on: [epic-bold-reachability-contract-app-adapter-step-1]
release_binding: app-v1.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 2: Refactor ConnectionManager to consume the adapter

## Current State

`ConnectionManager` stores reachability state directly and mixes state transitions
with transport side-effects in the same methods:

```dart
Future<void> _connect(PeerRecord peer) async {
  _cancelRetry();
  _cancelPing();
  _connectInFlight = true;
  _activePeer = peer;
  _emit(const StatusConnecting());
  final ch = await _factory(peer, token);
  _missedPings = 0;
  _emit(StatusOnline(ch));
  _startPing(peer, ch);
  _watchChannel(peer, ch);
}
```

```dart
void _scheduleRetry(PeerRecord peer) {
  final delay = _backoffFor(_retryAttempt);
  _emit(StatusRetrying(nextRetry: delay, attempt: _retryAttempt));
  _retryTimer = Timer(delay, () { _retryTimer = null; _retryAttempt++; _connect(peer); });
}
```

```dart
void _startWatchdog() {
  _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
    if (_status is StatusOnline) return;
    if (_connectInFlight) return;
    if (_retryTimer != null) return;
    _scheduleRetry(peer);
  });
}
```

## Target State

`ConnectionManager` delegates contract progression to `ReachabilityAdapter` and
uses adapter outputs to keep existing `ConnectionStatus` emissions unchanged:

```dart
void _startWatchdog() {
  _watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) {
    if (_status is StatusOnline) return;
    if (_reachability.connectInFlight) return;
    if (_retryTimer != null) return;
    if (_reachability.state == ReachabilityState.retrying) {
      _reachability.onRetryTimerFired();
      _connect(peer);
    }
  });
}

void _scheduleRetry(PeerRecord peer) {
  _reachability.onConnectFailedRetryable();
  final nextDelay = _reachability.nextRetryDelay;
  _emit(StatusRetrying(nextRetry: nextDelay, attempt: _reachability.retryAttempt));
  _retryTimer = Timer(nextDelay, () {
    _retryTimer = null;
    _reachability.onRetryTimerFired();
    _reachability.onConnectRequested();
    _connect(peer);
  });
}
```

## Implementation Notes

- Keep `StatusNoPeer`, `StatusOffline`, and `StatusRetrying` as public status
  contracts for existing UI/test callers.
- Preserve `_watchChannel` stale-channel guard, old channel `onDone` gating, and
  `adopt()` flow semantics exactly.
- `_startPing` keeps `25s` cadence and room liveness off switch (`_markActiveRoomOffline`).
- `_cancelPing()`/`_cancelRetry()` still clear live timers but let the adapter own
  counters/attempt state.
- `disconnect()`/`switchTo()`/`teardown` should call adapter `onStopRequested` and
  then explicit `StatusOffline`/`StatusNoPeer` emissions exactly as before.
- Do not touch protocol wire structures or room cache behavior in this step.

## Acceptance Criteria

- [ ] `_retryAttempt`, `_missedPings`, `_connectInFlight` removed from
  `ConnectionManager` class fields.
- [ ] Existing transport tests (`boot`, `connect success`, `factory failure`,
  `disconnect`, `switchTo`, watchdog no-op) still pass in principle.
- [ ] Public `ConnectionStatus` stream sequence semantics remain unchanged
  (offline/connecting/retrying/online transitions and retry attempt values).
- [ ] `StatusRetrying.nextRetry` and `attempt` are still derived from the existing
  contract ladder.

## Risk

High. This step changes the owner of the reconnect machine and has the greatest
risk for hidden ordering regressions (especially with in-flight switch/boot races).

## Rollback

Revert `ConnectionManager` transition rewrites and restore local in-class state
mutation while leaving the adapter file unused.

## Implementation notes
- Files changed: `app/lib/data/transport/connection_manager.dart`, `app/lib/data/transport/reachability_adapter.dart`, `app/test/transport/reachability_adapter_test.dart`.
- Tests added: adjusted adapter retry semantics test to pin the existing public `StatusRetrying.attempt=0` first-failure behavior.
- Discrepancies from design: Step 1's adapter incremented retry attempts on failure, but this story's acceptance criteria require preserving the existing `ConnectionManager` sequence where the first retry emits attempt `0` and the counter advances when the retry timer fires. The adapter was aligned with that public behavior while keeping retry delays sourced from the reachability contract.
- Adjacent issues parked: none.
- Verification: pending full app verification in this run after the remaining app story integrations.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- `ReachabilityAdapter.onConnectSucceeded()` resets `_retryAttempt` immediately, and `ConnectionManager._connect()` calls it as soon as the WebSocket factory returns (`app/lib/data/transport/reachability_adapter.dart:27-31`, `app/lib/data/transport/connection_manager.dart:529`). That violates the preserved offline-loop invariant documented in the same file (`connection_manager.dart:24-27`): retry backoff must reset only after real inbound app/Pi traffic (`onAppFrameObserved`), not after merely re-authenticating to the relay. With the Pi still down but the relay accepting sockets, each factory success can pin the next retry back to attempt 0 / 1s, re-opening the retry storm this adapter refactor is required to preserve. Split the adapter transition so factory success clears `connectInFlight`/missed pings without clearing `retryAttempt`, and keep `_retryAttempt = 0` on real inbound traffic or explicit stop/reset.

**Verification run**:
- `HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter analyze` — red on the pre-existing `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802`.
- Targeted tests passed: `HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter test test/protocol_codegen/dart_codegen_test.dart test/transport/reachability_adapter_test.dart test/transport/connection_manager_test.dart`.
- Full `HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter test` remains red on pre-existing unrelated actions/sync/chat session-identity failures; not used as the regression signal for this bounce.

## Implementation notes
- Files changed: `app/lib/data/transport/reachability_adapter.dart`, `app/lib/data/transport/connection_manager.dart`, `app/test/transport/reachability_adapter_test.dart`, `app/test/transport/connection_manager_test.dart`.
- Bounce fix: split the adapter's relay-socket success transition into `onRelayConnectionEstablished()`, which clears `connectInFlight` and missed pings but deliberately preserves `retryAttempt`; `ConnectionManager` now calls that method for factory/adopt successes. `retryAttempt` resets only on `onAppFrameObserved()` (real inbound app/Pi traffic) or explicit stop/reset.
- Regression coverage: added adapter coverage that relay connection success does not reset backoff, and a `ConnectionManager` offline-loop test proving consecutive factory-successes-without-inbound-traffic emit attempts `0`, `1`, then `2` with `1s`, `2s`, then `5s` delays.
- Public contract preserved: first `StatusRetrying` emission remains attempt `0`; the retry counter still advances when the retry timer fires.
- Verification: `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter test test/transport/reachability_adapter_test.dart test/transport/connection_manager_test.dart` passed. `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze` reported only the known unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802` and exited 1.
- Adjacent issues parked: none.

## Review (2026-06-30, fast-lane; previously bounced 2026-06-29)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified the bounce fix.

**Findings**: none above nit level. The 2026-06-29 bounce blocker (retry-storm via factory-success resetting `retryAttempt`) is resolved.

**Verification run (orchestrator)**:
- `git show --stat 38ab178` — only owned files: `app/lib/data/transport/{connection_manager,reachability_adapter}.dart` + their tests + this story; no collision with other app agents (ws_transport.dart / protocol.g.dart untouched).
- Bounce-fix confirmed in code: `onConnectSucceeded()` renamed `onRelayConnectionEstablished()`; the `_retryAttempt = 0` line was REMOVED from it (now only clears `_missedPings`/`_connectInFlight`). `retryAttempt` resets only in `onAppFrameObserved()` (real inbound traffic), `onStopRequested()`, and the stop/reset path — NOT on factory/adopt success. Both call sites in `connection_manager.dart` (factory success + adopt) updated. Doc comment states the invariant.
- Regression test `relay reconnect successes without inbound traffic keep advancing the backoff ladder` asserts attempts `0→1→2` with delays `1s→2s→5s` across three consecutive relay-reconnect-successes-without-inbound-traffic — directly closes the retry-storm vector from the bounce.
- `cd app && flutter test test/transport/reachability_adapter_test.dart test/transport/connection_manager_test.dart` (PUB_CACHE set) — 48/48 pass.
- `flutter analyze` — only the known-unrelated `axisAlignment` info.
- Acceptance criteria satisfied: `_retryAttempt`/`_missedPings`/`_connectInFlight` removed from `ConnectionManager` fields (owned by adapter); public `ConnectionStatus` sequence semantics unchanged; `StatusRetrying.attempt`/`nextRetry` still derived from the contract ladder.
