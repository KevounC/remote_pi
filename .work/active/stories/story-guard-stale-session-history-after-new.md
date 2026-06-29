---
id: story-guard-stale-session-history-after-new
kind: story
stage: review
tags: [app, pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
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
