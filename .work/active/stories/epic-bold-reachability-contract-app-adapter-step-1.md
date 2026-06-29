---
id: epic-bold-reachability-contract-app-adapter-step-1
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract-app-adapter
depends_on: [epic-bold-reachability-contract-state-machine]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Add the app reachability adapter runtime

## Current State

Reachability counters and booleans live directly on `ConnectionManager`, tightly
coupled to transport side effects and timers:

```dart
int _retryAttempt = 0;
int _missedPings = 0;
bool _connectInFlight = false;
Timer? _retryTimer;
Timer? _pingTimer;

Duration _backoffFor(int attempt) =>
    Duration(seconds: _kBackoff[attempt.clamp(0, _kBackoff.length - 1)]);
```

The contract artifact already exists in `protocol/schema/reachability.json`,
but `ConnectionManager` still drives local constants and state manually.

## Target State

Introduce a pure adapter in transport boundary that encapsulates reachability state,
attempt counters, and event handling, while staying protocol/domain-only:

```dart
// app/lib/data/transport/reachability_adapter.dart
import 'package:app/domain/value_objects/reachability.dart';

final class ReachabilityAdapter {
  ReachabilityState _state = ReachabilityState.offline;
  int _retryAttempt = 0;
  int _missedPings = 0;
  bool _connectInFlight = false;

  ReachabilityState get state => _state;
  int get retryAttempt => _retryAttempt;
  int get missedPings => _missedPings;
  bool get connectInFlight => _connectInFlight;
  Duration get nextRetryDelay => reachabilityBackoffForAttempt(_retryAttempt);

  void onConnectRequested() { _state = ReachabilityState.connecting; _connectInFlight = true; }
  void onConnectSucceeded() { _state = ReachabilityState.online; _retryAttempt = 0; _missedPings = 0; _connectInFlight = false; }
  void onConnectFailedRetryable() { _state = ReachabilityState.retrying; _connectInFlight = false; }
  void onTransportClosed() { _state = ReachabilityState.retrying; _missedPings = 0; }
  void onAppFrameObserved() { _retryAttempt = 0; _missedPings = 0; if (_state == ReachabilityState.retrying) _state = ReachabilityState.online; }
  void onPingMissed() {
    _missedPings++;
    if (_missedPings >= reachabilityHeartbeat.degradedAfterMissedAppPongs) {
      _state = ReachabilityState.degraded;
    }
  }
  void onRetryTimerFired() => _state = ReachabilityState.connecting;
  void onStopRequested() { _state = ReachabilityState.offline; _connectInFlight = false; _retryAttempt = 0; _missedPings = 0; }
  void reset() { _state = ReachabilityState.offline; _connectInFlight = false; _retryAttempt = 0; _missedPings = 0; }
}
```

## Design Notes

- Keep adapter free of `IChannel`, `timer`, and storage concerns so it is cheap to
  unit-test and safe for future protocol migration.
- Preserve the app-specific semantic that repeated ping misses means `degraded` but
  does **not** force offline; offline remains a transport-level terminal state.
- `reachabilityHeartbeat` and `reachabilityBackoffForAttempt` are imported from the
  domain value object to remove in-file duplication.

## Acceptance Criteria

- [ ] Adapter compiles in `app/lib/data/transport` with zero dependencies on WebSocket/UI.
- [ ] Adapter transition table covers `connecting`, `online`, `degraded`, `offline`,
  and `retrying` with attempt/miss counters.
- [ ] Existing connection behavior is not altered by this file alone.
- [ ] Adapter can emit equivalent `nextRetryDelay` and degraded-threshold values to
  current `ConnectionManager` behavior.

## Risk

Medium. Naming and transition ordering mistakes here can cascade into all reconnect
paths. Keep transition logic explicit and tested.

## Rollback

Delete `app/lib/data/transport/reachability_adapter.dart` and restore local fields
in `ConnectionManager`.
