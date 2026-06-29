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

- [ ] Add a deterministic test for: activate an empty/no-index session, call `clearActiveSession()`, then deliver an older pre-new `SessionHistory`; it must not repopulate the cleared box.
- [ ] Establish an explicit replacement generation or timestamp boundary even when no prior `session_started_at` is known.
- [ ] Preserve reconnect replay for the current session, including equal `session_started_at` histories that belong to the accepted current session.
