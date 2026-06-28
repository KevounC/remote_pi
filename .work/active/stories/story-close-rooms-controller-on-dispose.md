---
id: story-close-rooms-controller-on-dispose
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

# Close ConnectionManager rooms stream on dispose

`ConnectionManager.dispose()` closes status and presence controllers but not `_roomsController`.

## Acceptance Criteria

- [ ] Dispose closes `_roomsController` and cancels related timers/subscriptions safely.
- [ ] Add/adjust a test proving no rooms event can be emitted after dispose.
