---
id: epic-bold-relay-typed-actor-frame-dispatch-step-4
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-relay-typed-actor-frame-dispatch-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation

- Routed `DecodedRelayFrame::PiEnvelope` through `ConnectionActor::dispatch_pi_envelope` directly into `handle_pi_envelope` with the generated `PiEnvelopeFrame`; the previous typed-frame-to-raw-JSON reserialization shim was removed.
- Changed `handle_pi_envelope` to consume generated `PiEnvelopeFrame` and `AgentEnvelope`/`PiEnvelopeInFrame` types. Malformed `pi_envelope` compatibility stays isolated in `handle_malformed_pi_envelope` so `bad_envelope` can still recover only generic correlation fields (`id`, `from`) from the boundary raw value.
- Preserved relay opacity: the relay never parses generic envelope `body` or endpoint-owned `session_id`; tests keep `session_id` inside opaque bodies and verify it is carried unchanged.
- Preserved transport-error compatibility: `_relay` `pi_envelope_in` wrappers still carry `body.type: "transport_error"`, `reason` values `bad_envelope`/`not_authorized`/`offline`, and `re` correlation from the original generic envelope id when available.
- Preserved mesh authorization via authenticated `sender_peer_id`; added a test proving authorization and outgoing `from_pc` use the authenticated sender even when human-readable `envelope.from` is spoofed.
- Preserved peer-wide `forward_to_peer`; no `to_room` targeting or registry behavior changed.
- Regen verdict: not applicable; generator and generated protocol files were untouched.
- Verification: targeted `cargo test pi_forward --lib` passed (13/13); targeted `cargo test dispatch_malformed_pi_envelope --lib` passed (1/1); full relay `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build` passed. Full `cargo test` reported 89 lib tests, 0 main tests, and integration suites 3 + 13 + 8 + 10 + 2 + 19 all passing.

## Review

Approved (2026-06-30). Independently re-ran: relay `cargo fmt --check` clean;
`cargo clippy -- -D warnings` clean; `cargo test` 144 passed / 0 failed (89 lib +
3 integ + 13 mesh + 8 pi_forward + 10 presence + 2 parity + 19 rooms). Commit
`0589f70` scoped to connection_actor.rs + pi_forward.rs + story .md; relay-only,
no generated files touched (regen N/A).

Typed dispatch verified: `handle_pi_envelope` consumes generated `PiEnvelopeFrame`
(not raw `serde_json::Value`); `dispatch_pi_envelope` routes `DecodedRelayFrame::
PiEnvelope` directly. Opacity preserved: relay never parses generic envelope `body`
or endpoint-owned `session_id` (tests carry session_id unchanged in opaque bodies).
Transport-error shape compatible: `_relay` `pi_envelope_in` wrappers carry
`body.type: "transport_error"`, reasons `bad_envelope`/`not_authorized`/`offline`,
`re` correlation from original envelope id. Mesh auth via authenticated
`sender_peer_id` (NOT human-readable `envelope.from`) — verified by a test
proving spoofed `envelope.from` doesn't bypass authorization. Peer-wide
`forward_to_peer` preserved (no `to_room` targeting — deferred to
relay-opaque-targeting). `handle_malformed_pi_envelope` isolation (recovers only
`id`/`from` correlation from boundary raw value) is sound.
