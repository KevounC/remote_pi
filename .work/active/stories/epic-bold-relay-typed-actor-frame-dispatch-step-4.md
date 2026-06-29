---
id: epic-bold-relay-typed-actor-frame-dispatch-step-4
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-relay-typed-actor-frame-dispatch-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Route cross-PC `pi_envelope` through typed dispatch

**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contracts / relay opacity  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/pi_forward.rs`, generated `PiEnvelopeFrame`/agent-envelope types, `relay/src/peers/registry.rs`

## Current State

The raw switch calls `handle_pi_envelope` with a `serde_json::Value`; the handler then re-reads `to_pc` and `envelope` fields manually:

```rust
"pi_envelope" => {
    match handle_pi_envelope(&peer_id, &frame, &registry, &mesh, &mesh_auth).await {
        PiForwardResult::Forwarded => {}
        PiForwardResult::TransportError(err_msg) => {
            if sink.send(err_msg).await.is_err() { break; }
        }
    }
}
```

```rust
pub async fn handle_pi_envelope(
    sender_peer_id: &str,
    frame: &serde_json::Value,
    registry: &PeerRegistry,
    mesh: &MeshStore,
    cache: &MeshAuthCache,
) -> PiForwardResult {
    let to_pc = frame.get("to_pc").and_then(|v| v.as_str());
    let envelope = frame.get("envelope");
    /* authorization + forward_to_peer */
}
```

This keeps the cross-PC frame shape outside the generated contract and lets raw maps leak into business logic.

## Target State

`PiEnvelopeFrame` is generated from the protocol schema and handed directly to the cross-PC handler. The relay still treats the generic envelope body as opaque JSON; only the relay-owned wrapper is typed.

```rust
pub async fn handle_pi_envelope(
    sender_peer_id: &str,
    frame: PiEnvelopeFrame,
    registry: &PeerRegistry,
    mesh: &MeshStore,
    cache: &MeshAuthCache,
) -> PiForwardResult {
    if !cache.is_authorized(sender_peer_id, frame.to_pc.as_str(), mesh) {
        return PiForwardResult::TransportError(make_transport_error(
            Some(&frame.envelope),
            "not_authorized",
        ));
    }

    let outbound = PiEnvelopeInFrame {
        from_pc: sender_peer_id.to_owned(),
        envelope: frame.envelope,
    };

    if registry.forward_to_peer(frame.to_pc.as_str(), Message::Text(outbound.to_json_string())) {
        PiForwardResult::Forwarded
    } else {
        PiForwardResult::TransportError(make_transport_error(Some(&outbound.envelope), "offline"))
    }
}
```

`make_transport_error` may still read only generic envelope correlation fields (`id`, `from`) needed by `PROTOCOL.md`; it must not parse or validate inner `body` semantics.

## Implementation Notes

- Preserve current cross-PC behavior in this story, including peer-wide `forward_to_peer`; explicit `to_room` targeting belongs to `epic-bold-canonical-session-relay-opaque-targeting`.
- Preserve `not_authorized`, `offline`, and `bad_envelope` transport-error shape as `_relay` envelopes correlated by `re`.
- Keep mesh authorization based on authenticated `sender_peer_id`, never human-readable `envelope.from`.
- Add tests for typed bad-envelope rejection, authorization failure, offline failure, and successful forward serialization.

## Acceptance Criteria

- [ ] `handle_pi_envelope` accepts generated typed cross-PC frames, not raw `serde_json::Value`.
- [ ] The relay does not parse generic envelope bodies or endpoint-owned `session_id`.
- [ ] Transport-error shapes remain compatible with `PROTOCOL.md`.
- [ ] Mesh authorization still uses authenticated sender peer id and `MeshAuthCache`.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and targeted relay tests pass from `relay/`.

## Risk

Medium. Cross-PC delivery errors are user-visible through ACK/transport-error handling, so transport-error shape must not drift.

## Rollback

Restore the `serde_json::Value` signature on `handle_pi_envelope` and the raw `frame.get(...)` extraction. Because this story keeps peer-wide fanout unchanged, rollback is isolated.
