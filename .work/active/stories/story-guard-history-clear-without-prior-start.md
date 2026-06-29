---
id: story-guard-history-clear-without-prior-start
kind: story
stage: review
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

- [x] Add a deterministic test for: activate an empty/no-index session, call `clearActiveSession()`, then deliver an older pre-new `SessionHistory`; stale replacements are ignored across session-replacement generations until a current-session boundary is established.
- [x] Establish an explicit replacement generation or timestamp boundary even when no prior `session_started_at` is known.
- [x] Preserve reconnect replay for the current session, including equal `session_started_at` histories that belong to the accepted current session.

## Implementation notes
- Replaced the wall-clock floor in `clearActiveSession()` with a monotonic `_historyGeneration` replacement token.
  - `clearActiveSession()` now always increments `_historyGeneration` and resets `_activeSessionStartedAt` to `null`.
  - `SessionHistory` is now handled with the token captured from the listener path; stale histories from prior replacement generations are ignored.
  - The first `SessionHistory` accepted for the current generation establishes `_activeSessionStartedAt` from the Pi-provided value.
- `_applyHistory` now gates strictly on Pi-derived boundaries: drop only histories older than the accepted `_activeSessionStartedAt`, and accept equal/newer timestamps (updating `_activeSessionStartedAt` when newer).
- Updated regression coverage in `app/test/data/sync/sync_service_test.dart` to validate no-index replacement behavior, fresh replay below local-clock values, older replay drops after accept, and equal-timestamp replay.

## Review findings (2026-06-28)

**Verdict**: Approve

**Blockers**: none

**Important**: none

**Nits**:
- No issues.

**Notes**: Implemented generation-based replacement gating in `SyncService` and updated `app/test/data/sync/sync_service_test.dart` for empty/no-index replacement replay and boundary semantics. Verification:
- `cd /home/agent/forks/remote_pi/app && /opt/flutter/bin/flutter test --concurrency=1 test/data/sync/sync_service_test.dart`
- `cd /home/agent/forks/remote_pi/app && /opt/flutter/bin/flutter test --concurrency=1`
- `cd /home/agent/forks/remote_pi/app && /opt/flutter/bin/flutter analyze` (existing unrelated deprecated-member warning in `lib/ui/chat/widgets/input_bar.dart:802`)
