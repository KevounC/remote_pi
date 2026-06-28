---
id: story-fix-mobile-working-convergence-on-disconnect
kind: story
stage: implementing
tags: [app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Clear active chat working state when relay connection drops mid-turn

When `ConnectionManager` leaves `StatusOnline` mid-turn, `SyncService` cancels the message subscription but does not clear streaming/working runtime state. The chat can remain stuck in a stale streaming/stop state while the channel is null.

## Scope

- On non-`StatusOnline`, clear chat-local streaming state, active working reply id, flush timers, and input/cancel state.
- Do not erase durable room metadata that should still be corrected by relay snapshots.

## Acceptance Criteria

- [ ] Deterministic test: online working stream -> `StatusRetrying`/`StatusOffline` -> `SyncService.isWorking == false`, `streaming == null`, and no cancel target remains.
- [ ] Home/session room state still uses authoritative room snapshots when they arrive.
