---
id: epic-bold-reachability-contract-app-adapter-step-2
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract-app-adapter
depends_on: [epic-bold-reachability-contract-app-adapter-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
