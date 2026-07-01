---
id: epic-bold-reachability-contract-app-adapter-step-3
kind: story
stage: done
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract-app-adapter
depends_on: [epic-bold-reachability-contract-app-adapter-step-2]
release_binding: app-v1.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 3: Lock adapter behavior with transport + domain tests

## Current State

Transport tests cover `ConnectionManager` status states and reconnect edge cases,
but there are no dedicated unit tests around a dedicated reachability runtime,
and no adapter-level coverage for contract-derived behavior.

## Target State

Add or update tests that specifically assert the adapter and `ConnectionManager`
are observationally equivalent to the current behavior while using contract-backed
state values:

- `app/test/domain/reachability_test.dart` validates state names/backoff/heartbeat
  values against `../protocol/schema/reachability.json` (already aligned
  with state-machine work).
- `app/lib/data/transport/reachability_adapter.dart` gets focused unit tests for
  transition ordering and counter clamp behavior.
- Existing `app/test/transport/connection_manager_test.dart` is adjusted only for
  any adapter-driven event ordering that shifts internal scheduling without changing
  public status behavior.

Example test shape:

```dart
test('retries keep contract ladder and clamp', () {
  final a = ReachabilityAdapter();
  a.onConnectRequested();
  a.onConnectFailedRetryable();
  expect(a.retryAttempt, 0);
  expect(a.nextRetryDelay.inSeconds, 1);
  a.onRetryTimerFired(); a.onConnectFailedRetryable();
  expect(a.nextRetryDelay.inSeconds, 2);
});
```

## Implementation Notes

- Prefer pure adapter tests for deterministic timing and reduced flake.
- Keep transport tests to public `ConnectionStatus` and room/degrade behaviors:
  attempts, failures, reconnect, stale channel guard, no-op boot behavior.
- Do not introduce new long-running real-time timer assertions (25s wait); use fake
  clocks or adapter state transitions directly.

## Acceptance Criteria

- [ ] `flutter test test/domain/reachability_test.dart` passes.
- [ ] `flutter test test/transport/connection_manager_test.dart` passes.
- [ ] New adapter tests prove: backoff clamp after repeated attempts, 3-miss degraded
  threshold, and safe recovery of retry counter on app-frame ingress.
- [ ] No public status behavior regression in existing transport tests.

## Risk

Medium. Thin but strict tests can become brittle if internal contract fields are
renamed; keep assertions public-behavior first with a narrow adapter-focused
core.

## Rollback

Remove new adapter tests and revert temporary transport assertion reshapes while
keeping the feature behavior intact.

## Implementation

- `app/test/domain/reachability_test.dart` now validates the Dart projection against `protocol/schema/reachability.json` for state names/display names, backoff ladder and clamp behavior, heartbeat constants, and transition table membership. The transition membership assertions now compare map fields directly instead of relying on Dart `Map` identity.
- `app/test/transport/reachability_adapter_test.dart` covers deterministic adapter transitions: relay connection success preserves retry backoff, retry attempts advance only when the retry timer fires, repeated attempts clamp the next delay at the 30s contract ceiling, three missed app pongs degrade reachability, app-frame ingress restores online and resets retry/missed counters, and stop/reset returns offline.
- Re-checked the step-2 bounce invariant: `onRelayConnectionEstablished()` still does not reset `retryAttempt`; the existing `ConnectionManager` regression test preserves the public `0→1→2` retry ladder with `1s→2s→5s` delays when relay reconnects succeed without inbound app/Pi traffic.
- Verification: `flutter pub get` completed. `flutter analyze` reported only the known unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802` and no issues in this story's files. `flutter test test/domain/reachability_test.dart test/transport/reachability_adapter_test.dart test/transport/connection_manager_test.dart` passed `52/52`.

## Review

Fast-lane approved (2026-06-30). Independently re-ran `flutter test
test/domain/reachability_test.dart test/transport/reachability_adapter_test.dart
test/transport/connection_manager_test.dart` → 52/52; `flutter analyze` clean in
owned files (only known `axisAlignment` info). Commit `d6adcbb` scoped to test
files + story .md; collision guard held — did NOT touch connection_manager.dart
(owned by parallel projection-consumers-step-3). Bounce invariant re-verified:
`onRelayConnectionEstablished()` preserved (untouched in connection_manager.dart);
the existing `0→1→2` retry-ladder regression + `inbound message resets
_retryAttempt back to 0` test both green. Test-locking refactor with no source
behavior change.
