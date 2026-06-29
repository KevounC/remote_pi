---
id: story-guard-stale-session-history-after-new
kind: story
stage: done
tags: [app, pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: v0.5.0
gate_origin: null
archived_atop: unbound
archived_ref: 3dba904
created: 2026-06-28
updated: 2026-06-28
---

# Guard against stale session history after app-triggered New Session

After `session_new`, the app clears local state immediately and waits for `action_ok`, but a stale `session_history` from the dying session may still repopulate the cleared chat unless history is gated by session identity/time.

## Scope

- Use `session_started_at` or an explicit replacement generation to reject older history after `clearActiveSession()` / `session_new`.
- Preserve normal reconnect history replay for the current session.

## Acceptance Criteria

- [x] Deterministic test: clear active session, then receive older `SessionHistory`; it is dropped and does not repopulate the box.
- [x] Fresh session history still applies after replacement completes.

## Implementation notes
- Added `SyncService` session-start boundary tracking via `_activeSessionStartedAt`.
- `clearActiveSession()` now bumps the boundary to reject stale reconnect `SessionHistory` replay from the previous session.
- `_applyHistory()` now gates incoming `SessionHistory` by session-start boundary before write, updates the boundary on accepted history, and updates index `sessionStartedAt` only inside the accepted-history write path.
- `_loadIndex()` now restores the boundary from persisted `SessionIndexRecord.sessionStartedAt` so session continuity is preserved across activation/reload.

## Review (2026-06-28)

Verdict: Approve with comments

Findings:
- Important: `app/lib/data/sync/sync_service.dart:393` only bumps the stale-history boundary when `_activeSessionStartedAt` is already non-null, and `_applyHistory()` only rejects older history when that boundary exists at `app/lib/data/sync/sync_service.dart:681`. A New Session issued before the first accepted/persisted `session_started_at` can still be repopulated by a late stale `SessionHistory`. Filed follow-up `story-guard-history-clear-without-prior-start`.

Verification:
- Reviewed commit `63b1a26` diff against acceptance criteria.
- Ran `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/transport/connection_manager_test.dart test/data/sync/sync_service_test.dart test/main_lifecycle_test.dart` (pass).
