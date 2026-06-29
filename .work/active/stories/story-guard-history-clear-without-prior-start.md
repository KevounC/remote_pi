---
id: story-guard-history-clear-without-prior-start
kind: story
stage: implementing
tags: [app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-guard-stale-session-history-after-new]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Guard stale session history after clear when no prior start timestamp exists

Review of `story-guard-stale-session-history-after-new` found that `clearActiveSession()` only raises the history boundary when `_activeSessionStartedAt` is already non-null. If the user triggers New Session before any `SessionHistory` or persisted index has established that timestamp, a late stale `SessionHistory` from the prior session is accepted because `_applyHistory()` has no boundary to compare against.

## Acceptance Criteria

- [x] Add a deterministic test for: activate an empty/no-index session, call `clearActiveSession()`, then deliver an older pre-new `SessionHistory`; it must not repopulate the cleared box.
- [x] Establish an explicit replacement generation or timestamp boundary even when no prior `session_started_at` is known.
- [x] Preserve reconnect replay for the current session, including equal `session_started_at` histories that belong to the accepted current session.

## Implementation notes
- `clearActiveSession()` now always stamps a deterministic history floor:
  - increments existing `_activeSessionStartedAt` when present; otherwise initializes it with a local timestamp boundary (`DateTime.now().millisecondsSinceEpoch + 1`).
- Added regression test: `clearActiveSession establishes a history boundary even when session_started_at is not yet known` in `app/test/data/sync/sync_service_test.dart`.
  - Covers empty/no-index activation after clear, stale older history rejection, fresh replay acceptance, and equal-timestamp replay acceptance.
- Existing boundary/stale-history behavior for known timestamp sessions remains unchanged (`_applyHistory` still uses `<` and preserves equal timestamps).

## Review findings (2026-06-28)

**Verdict**: Request changes

**Blockers**:
- `app/lib/data/sync/sync_service.dart:395`: when no trusted Pi `session_started_at` exists, `clearActiveSession()` fabricates the stale-history floor from the phone clock. That floor is not comparable to the Pi extension's session clock, and in the normal New Session flow the Pi restamps/broadcasts the fresh `session_history` around the same time the app receives `action_ok`; the fresh current-session `session_started_at` can be less than the app's locally stamped floor. `_applyHistory()` then rejects it at `app/lib/data/sync/sync_service.dart:685`, leaving the newly cleared session unable to hydrate from the current replay. This fails the current-session replay guarantee for the no-prior-start case; use a Pi-derived boundary/generation or another explicit replacement token rather than a local wall-clock floor.

**Important**: none
**Nits**: none

**Notes**: Reviewed commits `5fe399c` and combined state with `3a91f78`; ran `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/data/sync/sync_service_test.dart` (pass). The existing test covers stale histories older than the local app clock and equal replay after an accepted fresh history, but not the fresh-replay-below-local-floor case above.
