---
id: epic-bold-canonical-session-relay-opaque-targeting-step-3
kind: story
stage: implementing
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
