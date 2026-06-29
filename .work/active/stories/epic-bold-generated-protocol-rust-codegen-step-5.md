---
id: epic-bold-generated-protocol-rust-codegen-step-5
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol-rust-codegen
depends_on: [epic-bold-generated-protocol-rust-codegen-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Generate cross-PC and mesh wire types, then add parity checks

**Priority**: High  
**Risk**: Medium  
**Source Lens**: duplicated wire structs / contract-test gap  
**Files**: `relay/src/protocol/generated/cross_pc.rs`, `relay/src/protocol/generated/mesh.rs`, `relay/src/handlers/pi_forward.rs`, `relay/src/mesh/types.rs`, `relay/tests/` or focused module tests, `protocol/fixtures/relay/`, `protocol/fixtures/cross-pc/`

## Current State

Cross-PC forwarding reads raw JSON and mesh HTTP DTOs are handwritten separately:

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
    // authorization + verbatim forward
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeshEnvelopeWire {
    pub blob: String,
    pub sig: String,
}
```

## Target State

Generated cross-PC and mesh wire structs remove the remaining Rust hand mirrors while keeping opaque bodies as JSON values:

```rust
// relay/src/protocol/generated/cross_pc.rs
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AgentEnvelope {
    pub from: String,
    pub to: serde_json::Value,
    pub id: String,
    pub re: Option<String>,
    pub body: serde_json::Value,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct PiEnvelopeFrame {
    pub to_pc: String,
    pub envelope: AgentEnvelope,
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct PiEnvelopeInFrame {
    pub from_pc: String,
    pub envelope: AgentEnvelope,
}
```

```rust
// relay/src/protocol/generated/mesh.rs
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct MeshEnvelopeWire { pub blob: String, pub sig: String }
```

## Implementation Notes

- Preserve relay opacity: generic envelope `body` remains `serde_json::Value`; the relay does not parse app↔Pi inner chat bodies or endpoint-owned `session_id`.
- Preserve current `transport_error` shape with `_relay`, `re`, and `body.type = "transport_error"`.
- Keep mesh decoded/internal types (`MeshEnvelope`, `MeshRecord`) handwritten if they are not wire DTOs; only JSON request/response/query structs need generation.
- Add parity tests that deserialize relay/cross-PC fixtures through generated Rust types and serialize representative current frames unchanged.
- Leave explicit cross-PC room targeting to `epic-bold-canonical-session-relay-opaque-targeting`; this step preserves peer-wide `forward_to_peer` behavior until that behavior-changing item lands.

## Acceptance Criteria

- [ ] `pi_envelope`, `pi_envelope_in`, generic `AgentEnvelope`, and mesh HTTP wire DTOs are generated from the shared schema/IR.
- [ ] `pi_forward.rs` and `mesh/types.rs` consume generated wire DTOs or re-export them rather than redefining them by hand.
- [ ] Cross-PC `body` and app↔Pi `ct` remain opaque to the relay.
- [ ] Rust parity tests validate relay/cross-PC fixtures and catch omitted generated variants.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass from `relay/`.

## Risk

Medium. The main risk is over-typing `AgentEnvelope.body` or `session_id` and accidentally moving endpoint session semantics into the relay.

## Rollback

Revert cross-PC/mesh generated-type consumption and restore raw JSON parsing in `pi_forward.rs` plus handwritten wire DTOs in `mesh/types.rs`. Earlier generated outer/control/room types can remain.
