---
id: story-cap-relay-control-frame-fanout
kind: story
stage: implementing
tags: [relay, security]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Cap relay control-frame subscription fanout

Relay presence/rooms control frames accept arbitrary peer arrays and can generate unbounded fanout through unbounded channels.

## Scope

- Add a maximum peers-per-control-frame limit for subscribe/check frames.
- Add basic per-connection rate limiting or cost limiting for presence/rooms checks.
- Return/drop with privacy-safe warnings for oversized requests.

## Acceptance Criteria

- [ ] Oversized `subscribe_presence`, `presence_check`, `subscribe_rooms`, and `rooms_check` requests are bounded.
- [ ] Tests cover limits and normal small requests.
- [ ] Logs do not include payload content or secrets.
