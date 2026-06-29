---
id: story-cap-relay-control-frame-fanout
kind: story
stage: review
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

- [x] Oversized `subscribe_presence`, `presence_check`, `subscribe_rooms`, and `rooms_check` requests are bounded.
- [x] Tests cover limits and normal small requests.
- [x] Logs do not include payload content or secrets.

## Implementation notes

Changed files:

- `relay/src/handlers/peer.rs` — added `MAX_CONTROL_FRAME_PEERS`, per-connection check peer-cost limiting, bounded peer-list parsing, and privacy-safe warning metadata for oversized/rate-limited control frames.
- `relay/tests/presence_test.rs` — covered oversized `subscribe_presence` and `presence_check` drops while preserving existing normal small-request coverage.
- `relay/tests/rooms_test.rs` — covered oversized `subscribe_rooms` and `rooms_check` drops while preserving existing normal small-request coverage.

Verification from `relay/`:

- `cargo fmt --check` — passed.
- `cargo clippy -- -D warnings` — passed after concurrently modified relay mesh-auth files settled.
- `cargo test` — passed (41 unit tests, 50 integration/doc tests); emitted one pre-existing/concurrent `dead_code` warning in `relay/src/handlers/pi_forward.rs` during lib tests.
