---
id: epic-bold-reachability-contract-app-adapter-step-3
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-reachability-contract-app-adapter
depends_on: [epic-bold-reachability-contract-app-adapter-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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