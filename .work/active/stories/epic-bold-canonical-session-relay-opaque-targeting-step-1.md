---
id: epic-bold-canonical-session-relay-opaque-targeting-step-1
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-canonical-session-relay-opaque-targeting
depends_on: [epic-bold-canonical-session-identity-model]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Add explicit cross-PC room target parsing

## Current State

```rust
let to_pc = frame.get("to_pc").and_then(|v| v.as_str());
let envelope = frame.get("envelope");

let (to_pc, envelope) = match (to_pc, envelope) {
    (Some(t), Some(e)) if e.is_object() && !t.is_empty() => (t, e),
    _ => return PiForwardResult::TransportError(make_transport_error(frame.get("envelope"), "bad_envelope")),
};
```

## Target State

```rust
let to_pc = frame.get("to_pc").and_then(|v| v.as_str());
let to_room = frame.get("to_room").and_then(|v| v.as_str());
let envelope = frame.get("envelope");

let (to_pc, to_room, envelope) = match (to_pc, to_room, envelope) {
    (Some(pc), Some(room), Some(e))
        if !pc.is_empty() && !room.is_empty() && e.is_object() => (pc, room, e),
    _ => {
        return PiForwardResult::TransportError(make_transport_error(
            frame.get("envelope"),
            "bad_envelope",
        ));
    }
};
```

## Implementation Notes

- Treat `to_room` as relay-owned routing metadata only; do not derive it from `session_id` and do not parse the generic envelope body.
- Add tests for missing `to_room`, empty `to_room`, missing `to_pc`, non-object `envelope`, and valid `to_pc`/`to_room` extraction.
- Mirror the field into future generated cross-PC frame definitions; do not create a separate Rust-only target model once generated code lands.
- This story intentionally depends on `epic-bold-canonical-session-identity-model`, which locked the relay's session-blind posture.

## Acceptance Criteria

- [ ] `pi_envelope` with missing/empty `to_room` returns `bad_envelope` in the clean-room path.
- [ ] Valid `to_pc`/`to_room` frames proceed to authorization without inspecting `envelope.body`.
- [ ] Tests prove `session_id` inside the generic envelope body is irrelevant to relay parsing.
- [ ] Relay fmt/clippy/tests pass for the touched module.

## Risk

Medium. The wrapper contract changes, and sender-side code must provide `to_room`; however the relay-side failure mode is explicit `bad_envelope` rather than silent fanout.

## Rollback

Revert the `to_room` extraction and tests; this restores the legacy `to_pc`-only parser but must be paired with re-enabling the old fanout path if later steps already landed.

## Implementation notes
- Files changed: `relay/src/handlers/pi_forward.rs`, `relay/tests/pi_forward_test.rs`.
- Tests added: relay unit coverage for missing `to_room`, empty `to_room`, non-object `envelope`, and a valid `to_pc`/`to_room` frame whose `body.session_id` remains irrelevant to relay parsing; integration sender helper now includes `to_room`.
- Discrepancies from design: none; this step parses and validates `to_room` but intentionally leaves the legacy `forward_to_peer` delivery path for the later room-targeted forwarding story.
- Adjacent issues parked: none.
- Verification: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed from `relay/`.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane substrate review. Implementation commit `76a6e53` was inspected. `handle_pi_envelope` now requires non-empty `to_pc` and `to_room` plus object `envelope`; missing/empty `to_room` returns `bad_envelope`; valid `to_pc`/`to_room` proceeds to mesh authorization while leaving `envelope.body.session_id` opaque and unparsed. This story intentionally only parses `to_room`; room-targeted forwarding remains a later step. Verification run during review: `cd relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed. Item advanced to `stage: done`.
