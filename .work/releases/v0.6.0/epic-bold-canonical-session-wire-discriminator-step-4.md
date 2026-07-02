---
id: epic-bold-canonical-session-wire-discriminator-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-canonical-session-wire-discriminator
depends_on: [epic-bold-canonical-session-wire-discriminator-step-3]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 4: Replace cross-PC peer-wide fanout with explicit room targeting while preserving relay opacity

## Current State
```rust
// relay/src/handlers/pi_forward.rs
if registry.forward_to_peer(to_pc, msg) {
    PiForwardResult::Forwarded
}

// relay/src/peers/registry.rs
pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool {
    for ((p, _), v) in lock.iter() {
        if p == peer_id { /* sends to every live room */ }
    }
}
```

This can deliver a cross-PC envelope to every live room for `to_pc`, one of the contamination vectors called out by the parent epic.

## Target State
```rust
let to_room = frame.get("to_room").and_then(|v| v.as_str()).filter(|s| !s.is_empty());
let Some(to_room) = to_room else {
    return PiForwardResult::TransportError(make_transport_error(Some(envelope), "bad_envelope"));
};

if registry.forward_to_room(to_pc, to_room, msg) {
    PiForwardResult::Forwarded
} else {
    PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
}
```

## Implementation Notes
- `pi_envelope` adds required `to_room`; `pi_envelope_in` still carries the inner envelope verbatim plus authenticated `from_pc`.
- Relay must not inspect `session_id` in `ct` or generic envelope bodies, must not store it, and must not log it.
- Keep control-frame broadcasts (`peer_online`, `room_announced`, `room_meta_updated`) on their existing subscriber fanout paths; only cross-PC Pi envelope delivery loses peer-wide room fanout.
- `OuterEnvelope` app↔Pi room defaulting is a separate compatibility seam. For this bugfix, no-room app envelopes in `WsTransport` are dropped before app state mutation; future generated-protocol work can remove `default_room` at the schema boundary.

## Acceptance Criteria
- [ ] A `pi_envelope` missing `to_room` returns `transport_error: bad_envelope`.
- [ ] A `pi_envelope` for `to_room=room-b` reaches only room B, not every live room for `to_pc`.
- [ ] Relay tests prove `session_id` inside opaque payload/body is carried unchanged and uninspected.
- [ ] Existing presence/rooms subscriber broadcasts still fan out as before.
- [ ] `cargo fmt --check` and targeted relay tests pass.

## Risk
Medium. Existing cross-PC senders must learn `to_room`; otherwise they receive `bad_envelope`. This is intentional clean-room behavior for the fork-private bugfix.

## Rollback
Restore `forward_to_peer` use and client omission of `to_room`, knowingly re-opening the cross-room fanout vector. Do not roll back by teaching the relay to parse `session_id`.

## Implementation notes
- Files changed: `relay/tests/pi_forward_test.rs`; verified existing production code in `relay/src/handlers/pi_forward.rs` and `relay/src/peers/registry.rs` already requires non-empty `to_room`, calls `PeerRegistry::forward_to_room`, and has no `forward_to_peer` call site.
- Tests added: `missing_to_room_returns_transport_error_bad_envelope` in `relay/tests/pi_forward_test.rs`; existing unit tests cover empty/missing `to_room`, two-room targeted delivery, and verbatim opaque `session_id` carry in the inner envelope.
- Verification: `cd /home/agent/projects/remote_pi/relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test` — passed; `pi_forward_test` now runs 7 tests.
- Discrepancies from design: implementation was already present in the checked-out relay source before this stride, so this pass landed an integration regression for the explicit missing-`to_room` wire case and advanced the story. Existing `pi_envelope_in` includes relay-owned `to_room` in addition to authenticated `from_pc` and the verbatim inner envelope, matching adjacent relay opaque-targeting work.
- Adjacent issues parked: none.

## Review (2026-06-30, fast-lane)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 8bad735` — only `relay/tests/pi_forward_test.rs` + this story file changed; no stray files.
- Confirmed `forward_to_room` already present in `relay/src/peers/registry.rs:372` and `relay/src/handlers/pi_forward.rs:190` (from prior identity-model/relay-opaque-targeting commits), so this step's remaining job was the regression-test lock — legit land-mode.
- `cd relay && cargo test --test pi_forward_test` — 7/7 pass, incl. new `missing_to_room_returns_transport_error_bad_envelope` (live-relay integration test asserting `bad_envelope` transport error + envelope correlation; opaque `session_id` carried in body unchanged and uninspected).
- Acceptance criteria all satisfied: missing `to_room`→`bad_envelope`; targeted two-room delivery; `session_id` opaque/uninspected; control broadcasts preserved; fmt/clippy/test green.
