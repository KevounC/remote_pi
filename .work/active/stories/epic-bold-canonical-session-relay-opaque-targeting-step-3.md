---
id: epic-bold-canonical-session-relay-opaque-targeting-step-3
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-canonical-session-relay-opaque-targeting
depends_on: [epic-bold-canonical-session-relay-opaque-targeting-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Preserve transport-error semantics and inbound target metadata

## Current State

```rust
let outbound = serde_json::json!({
    "type": "pi_envelope_in",
    "from_pc": sender_peer_id,
    "envelope": envelope, // verbatim
});
let msg = Message::Text(outbound.to_string());

if registry.forward_to_peer(to_pc, msg) {
    PiForwardResult::Forwarded
} else {
    PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
}
```

## Target State

```rust
let outbound = serde_json::json!({
    "type": "pi_envelope_in",
    "from_pc": sender_peer_id,
    "to_room": to_room,
    "envelope": envelope, // verbatim
});
let msg = Message::Text(outbound.to_string());

if registry.forward_to_room(to_pc, to_room, msg) {
    PiForwardResult::Forwarded
} else {
    PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
}
```

## Implementation Notes

- Keep authorization order: validate wrapper shape, verify `sender_peer_id`/`to_pc` sibling membership, then route to `to_room`.
- Unknown `to_room` under an online `to_pc` returns the existing `offline` transport error because the addressed target is not live.
- Include `to_room` in `pi_envelope_in` so the receiving extension can validate that the inbound target matches the local connection/session guard; do not include or derive `session_id` at the relay.
- Preserve `_relay` error envelope fields: `from: "_relay"`, `to` copied from original `envelope.from` when present, fresh id, `re` copied from original id, and `body.reason`.

## Acceptance Criteria

- [ ] Successful `pi_envelope` delivery emits `pi_envelope_in` with `from_pc`, `to_room`, and verbatim `envelope`.
- [ ] Unknown destination room returns `transport_error: offline` correlated to the original envelope id.
- [ ] `not_authorized` and `bad_envelope` behavior remains compatible with `PROTOCOL.md`.
- [ ] No relay logs or errors include `ct`, generic envelope body content, or `session_id`.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Medium. The relay-owned inbound wrapper adds `to_room`, which generated protocol and typed actor consumers must carry consistently.

## Rollback

Revert `pi_envelope_in.to_room` emission and route through `forward_to_peer`; transport-error helper can remain if unchanged.

## Implementation notes
- Files changed: `relay/tests/pi_forward_test.rs`.
- Tests added: `unknown_destination_room_returns_transport_error_offline`; strengthened happy path to assert `pi_envelope_in.to_room` and verbatim carry of an opaque `session_id` inside the generic envelope body.
- Discrepancies from design: implementation code for `to_room` parsing, `forward_to_room`, and inbound `to_room` was already present from previous steps; this story locked the transport-error and inbound-metadata contract with integration coverage.
- Adjacent issues parked: none.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**:
- Adjacent issues parked: the current generated cross-PC schema/types (`protocol/schema/cross-pc.schema.json`, `relay/src/protocol/generated/cross_pc.rs`) still omit `to_room`; this story is raw-relay/test coverage only, but the generated-protocol/typed-dispatch follow-up must include the relay-owned target field before those types become authoritative.

**Nits**:
- `relay/tests/pi_forward_test.rs` has a stale doc comment above `unknown_destination_room_returns_transport_error_offline` saying Pi-B is not connected, while the test intentionally connects Pi-B and targets an unknown room.

**Notes**: Reviewed implementation commit `c04fedac` and the exercised relay path in `relay/src/handlers/pi_forward.rs` plus `relay/src/peers/registry.rs`. The new happy-path assertion verifies `pi_envelope_in` carries authenticated `from_pc`, relay-owned `to_room`, and the generic envelope unchanged including opaque `body.session_id`; the unknown-room integration test verifies `transport_error: offline` is correlated via `re` and addressed back to the original `envelope.from`. Source inspection confirms the relay validates wrapper fields (`to_pc`, `to_room`, object `envelope`), authorizes by authenticated sender/to_pc, routes by `forward_to_room(to_pc, to_room, ...)`, and does not log or parse generic envelope body/session semantics on this path. Verification run from `relay/`: `cargo fmt --check` passed; `cargo clippy -- -D warnings` passed; `cargo test --test pi_forward_test` passed (6 passed); `cargo test` passed full suite (63 lib, 3 integration, 13 mesh, 6 pi_forward, 10 presence, 19 rooms, doctests 0).
