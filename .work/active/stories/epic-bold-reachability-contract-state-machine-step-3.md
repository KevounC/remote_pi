---
id: epic-bold-reachability-contract-state-machine-step-3
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract-state-machine
depends_on: [epic-bold-reachability-contract-state-machine-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Add the Dart Reachability projection module

**Priority**: High
**Risk**: Low
**Source Lens**: missing abstraction / pattern drift
**Files**: `app/lib/domain/value_objects/reachability.dart`, `app/test/domain/reachability_test.dart`

## Current State

The app has the cleanest explicit state machine, but it is data-transport-specific and omits the named `Degraded` state even though `_markActiveRoomOffline()` already models that condition:

```dart
// app/lib/data/transport/connection_manager.dart
sealed class ConnectionStatus { const ConnectionStatus(); }
class StatusNoPeer extends ConnectionStatus { const StatusNoPeer(); }
class StatusConnecting extends ConnectionStatus { const StatusConnecting(); }
class StatusOnline extends ConnectionStatus { final IChannel channel; const StatusOnline(this.channel); }
class StatusRetrying extends ConnectionStatus { final Duration nextRetry; final int attempt; const StatusRetrying({required this.nextRetry, required this.attempt}); }
class StatusOffline extends ConnectionStatus { final String reason; final bool canRetry; const StatusOffline({required this.reason, this.canRetry = true}); }
const _kBackoff = [1, 2, 5, 10, 30];
```

## Target State

Add a UI/storage/network-free domain value object module that app adapters can consume later:

```dart
// app/lib/domain/value_objects/reachability.dart
enum ReachabilityState { connecting, online, degraded, offline, retrying }

extension ReachabilityStateLabel on ReachabilityState {
  String get displayName => switch (this) {
    ReachabilityState.connecting => 'Connecting',
    ReachabilityState.online => 'Online',
    ReachabilityState.degraded => 'Degraded',
    ReachabilityState.offline => 'Offline',
    ReachabilityState.retrying => 'Retrying',
  };
}

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

const reachabilityHeartbeat = ReachabilityHeartbeat(
  appProtocolPing: Duration(seconds: 25),
  relayWsPing: Duration(seconds: 25),
  extensionLivenessCheck: Duration(seconds: 20),
  extensionLivenessTimeout: Duration(seconds: 70),
  degradedAfterMissedAppPongs: 3,
);

final class ReachabilityHeartbeat {
  const ReachabilityHeartbeat({
    required this.appProtocolPing,
    required this.relayWsPing,
    required this.extensionLivenessCheck,
    required this.extensionLivenessTimeout,
    required this.degradedAfterMissedAppPongs,
  });

  final Duration appProtocolPing;
  final Duration relayWsPing;
  final Duration extensionLivenessCheck;
  final Duration extensionLivenessTimeout;
  final int degradedAfterMissedAppPongs;
}
```

Add a transition registry as a typed list/set so the app adapter can assert legal moves without duplicating stringly switch logic.

## Implementation Notes

- Place this in `domain/value_objects` because it is a transport/domain contract, not a widget or `IChannel` carrier.
- Keep `ConnectionStatus` untouched in this story; `epic-bold-reachability-contract-app-adapter` maps it to/from `ReachabilityState` later.
- Tests should read `../.orchestration/contracts/reachability.json` from the repo root relative to `app/` and compare state names, backoff seconds, heartbeat fields, and transitions.
- Do not import `dart:io` from production code; reading JSON is test-only.

## Acceptance Criteria

- [ ] `flutter test test/domain/reachability_test.dart` passes from `app/`.
- [ ] Production reachability value objects import no Flutter, WebSocket, storage, or UI packages.
- [ ] Dart tests fail if the interim JSON contract states/backoffs/heartbeat/transitions drift.
- [ ] No `ConnectionManager` behavior changes in this story.

## Risk

Low. This adds pure domain constants/types plus tests. Risk is path brittleness in tests or accidental layer violation if the module is placed under `data/transport` instead of domain.

## Rollback

Delete the Dart reachability value object and its test. Existing `ConnectionManager` behavior remains unchanged.
