---
id: story-preserve-pending-send-backstop-on-disconnect
kind: story
stage: done
tags: [app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-fix-mobile-working-convergence-on-disconnect]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Preserve pending-send failure convergence when the relay disconnects

Review of `story-fix-mobile-working-convergence-on-disconnect` found that the non-online reset path cancels pending send backstop timers through `_resetTurnState()`. If a user sends while online and the relay drops before the Pi echoes the message, the optimistic pending row can survive without any timer to convert it into a visible failure. A later reconnect/session sync preserves pending rows that are absent from history, so the bubble can remain pending indefinitely.

## Acceptance Criteria

- [x] Add a deterministic `SyncService` test for: online `sendMessage()` creates a pending row, status transitions to retrying/offline before echo, reconnect/session sync does not leave the row pending forever.
- [x] Preserve or re-arm the pending-send backstop across disconnects, or explicitly fail/clear the pending row on disconnect with a visible reason.
- [x] Continue to clear chat-local streaming/working/cancel state on every non-`StatusOnline` transition.

## Implementation notes
- Kept `SyncService` chat-local reset semantics intact for working/streaming and kept durable room index untouched on non-online transitions.
- Added optional `_resetTurnState({bool clearPendingSendTimers = false})` and changed non-online `_onStatus` path to preserve timer-backed pending-send backstops (`clearPendingSendTimers: false`) while still clearing turn-local UI state.
- Kept session-switch semantics by calling `_resetTurnState(clearPendingSendTimers: true)` from `activate(...)` so stale timers from another chat are not leaked into the new session.
- Updated disconnect test to use deterministic async waits (`StatusRetrying` await + periodic `_settle()`): confirms queued input/working/streaming/cancel state are cleared on disconnect, confirms the pending timer remains armed across the drop, advances through settle windows so the row fails visibly, and verifies reconnect does not reintroduce a stuck pending bubble.

## Review (2026-06-28)

**Verdict**: Approve with comments

**Blockers**: none
**Important**:
- `story-make-pending-backstop-disconnect-test-deterministic` — `app/test/data/sync/sync_service_test.dart:393` waits for the backstop with repeated real-time `_settle()` sleeps. The test is behavior-asserting and passes, but the timer boundary should be deterministic for this lifecycle regression.
**Nits**: none

**Notes**: Reviewed commit `3a91f78` and combined state with `5fe399c`. `_resetTurnState(clearPendingSendTimers: false)` preserves pending backstops on non-online transitions while clearing chat-local state, and `activate(...)` still clears timers on session switch. Ran `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/data/sync/sync_service_test.dart` (pass).
