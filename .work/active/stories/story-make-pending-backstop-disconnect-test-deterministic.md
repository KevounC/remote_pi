---
id: story-make-pending-backstop-disconnect-test-deterministic
kind: story
stage: review
tags: [app, tests]
parent: epic-remote-session-resilience-refactor
depends_on: [story-preserve-pending-send-backstop-on-disconnect]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Make the pending-send disconnect backstop regression test deterministic

Review of `story-preserve-pending-send-backstop-on-disconnect` found that the regression test proves the intended behavior, but its timeout assertion advances via repeated real-time `_settle()` sleeps rather than a deterministic timer/stream boundary.

## Scope

- Replace the repeated wall-clock settle loop in `app/test/data/sync/sync_service_test.dart` for `disconnect while online keeps pending backstops and avoids stuck bubbles` with a deterministic wait for the pending row to fail, a fake-clock seam, or another explicit synchronization point.
- Preserve the existing behavior assertions: non-online status clears queued text/working/streaming/cancel state, keeps the pending timer armed across the drop, converts the pending row into a visible send-timeout failure, and reconnect does not resurrect a stuck pending row.

## Acceptance Criteria

- [x] The disconnect pending-backstop regression test no longer depends on an arbitrary stack of `Future.delayed` / `_settle()` sleeps to wait out the timer.
- [x] The test still fails if non-online `_resetTurnState` cancels pending-send backstops.
- [x] `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/data/sync/sync_service_test.dart` passes.

## Implementation notes
- Kept all existing behavioral assertions from the regression test intact.
- Set the timeout under test to `Duration.zero` for this deterministic regression run and used a bounded yield loop (`Duration.zero`) to wait for the row to flip to the timeout-failure shape.
- Removed the prior fixed 5× `_settle()` delay wall-clock wait entirely; failure-path synchronization is now an explicit row-state polling gate with a hard cap and loud failure when unmet.
- No production behavior was changed; only test timing/sequencing was adjusted.