---
id: story-add-mobile-resume-hydration
kind: story
stage: implementing
tags: [app, pi-extension, relay]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review, story-fix-mobile-working-convergence-on-disconnect]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Add mobile resume hydration for room/session state

App lifecycle resume currently restarts mesh polling only. It does not explicitly re-check the relay WebSocket, replay presence/room subscriptions, request room snapshots, or request active chat sync.

## Scope

- Add a resume hook that asks connection/session services to reconcile visible state.
- If online, replay subscriptions and request presence/rooms snapshots for known peers; request active session sync.
- If the socket is suspect or retrying, trigger/reuse the normal reconnect path without blocking background/resume handlers.

## Acceptance Criteria

- [ ] Deterministic test proves resume triggers room/presence/session hydration even when cached state appears online.
- [ ] Manual smoke plan covers background during idle and during working, then foreground.
- [ ] No network wait is introduced in pause/background handling.
