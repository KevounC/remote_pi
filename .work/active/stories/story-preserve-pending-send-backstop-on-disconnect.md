---
id: story-preserve-pending-send-backstop-on-disconnect
kind: story
stage: implementing
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

- [ ] Add a deterministic `SyncService` test for: online `sendMessage()` creates a pending row, status transitions to retrying/offline before echo, reconnect/session sync does not leave the row pending forever.
- [ ] Preserve or re-arm the pending-send backstop across disconnects, or explicitly fail/clear the pending row on disconnect with a visible reason.
- [ ] Continue to clear chat-local streaming/working/cancel state on every non-`StatusOnline` transition.
