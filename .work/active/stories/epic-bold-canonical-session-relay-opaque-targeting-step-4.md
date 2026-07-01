---
id: epic-bold-canonical-session-relay-opaque-targeting-step-4
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-canonical-session-relay-opaque-targeting
depends_on: [epic-bold-canonical-session-relay-opaque-targeting-step-3]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Lock the opaque relay boundary with regression tests and comments

## Current State

```rust
// registry.rs today exposes both targeted forward(...) and peer-wide forward_to_peer(...).
// pi_forward.rs conventionally treats envelope as verbatim, but has no room-target regression test.
```

## Target State

```rust
// Cross-PC data-plane forwarding is always room-targeted: (to_pc, to_room).
// Any session_id inside ct, room metadata, or AgentEnvelope.body is endpoint-owned opaque data.
```

## Implementation Notes

- Add a test that embeds `session_id` in `envelope.body` and proves the forwarded `pi_envelope_in.envelope` is byte/JSON-value equivalent except for relay-owned wrapper fields.
- Add a targeted-room regression test that registers two rooms under one peer and proves only `to_room` receives the frame.
- Remove stale comments that say cross-PC lacks room knowledge (`"where the relay has Pi-B's pubkey but not its room_id"`). Replace with the room-targeted invariant.
- Keep `RoomMeta.session_id` documented as opaque bootstrap metadata; it is not a routing key, lookup key, log key, or metric dimension.

## Acceptance Criteria

- [ ] Tests fail if `pi_forward` parses or branches on `session_id`.
- [ ] Comments and module docs no longer describe peer-wide fanout as the expected cross-PC path.
- [ ] `RoomMeta.session_id` remains opaque metadata and is not used by registry lookup or forwarding.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Low. This is a regression-lock and documentation cleanup step after the behavior switch.

## Rollback

Revert the tests/comments only if they block an emergency rollback to peer-wide forwarding; do not leave comments claiming room-targeted routing while fanout is restored.

## Implementation notes

- Added `relay/tests/pi_forward_test.rs` integration coverage for endpoint-owned `session_id` opacity: forwarded `pi_envelope_in` wrappers contain only relay-owned fields and preserve the generic envelope JSON unchanged.
- Added an end-to-end targeted-room regression: one destination peer connected in `main` and `work`, a `to_room=work` frame reaches only `work` and does not fan out to `main`.
- Cleaned relay comments in `relay/src/handlers/pi_forward.rs` and `relay/src/peers/registry.rs` to state the `(to_pc, to_room)` targeting invariant and opaque session metadata boundary.
- Verification from `relay/`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed; `tests/pi_forward_test.rs` now runs 9 tests.

## Review (2026-06-30, fast-lane)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 62eaef2` — only owned files: `relay/src/handlers/pi_forward.rs` (comments), `relay/src/peers/registry.rs` (comments), `relay/tests/pi_forward_test.rs` (tests) + this story. No behavior change to forward path; no collision with other relay agents.
- New regression tests (pi_forward_test now 9, up from 7): `session_id_in_body_is_opaque_and_forwarded_verbatim` (embeds `session_id` at body/nested-object/array levels, asserts verbatim carry in `pi_envelope_in.envelope` — fails if `pi_forward` parsed/branched on it) + `targeted_room_receives_frame_without_peer_wide_fanout` (two rooms under one peer, only `to_room` receives).
- `cd relay && cargo test --test pi_forward_test` — 9/9 pass; `cargo fmt --check` clean; `cargo clippy -- -D warnings` clean.
- Stale comments removed (`grep` for "not its room_id"/"lacks room knowledge" → absent). Room-targeted invariant documented in `pi_forward.rs` module doc + `registry.rs:371`. `RoomMeta.session_id` remains opaque bootstrap metadata (not a routing/lookup/log/metric key).
- Acceptance criteria satisfied: tests fail if `pi_forward` branches on `session_id`; comments no longer describe peer-wide fanout as expected; `RoomMeta.session_id` opaque; fmt/clippy/tests green.
