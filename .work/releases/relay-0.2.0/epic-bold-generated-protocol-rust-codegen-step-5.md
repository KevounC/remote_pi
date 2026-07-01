---
id: epic-bold-generated-protocol-rust-codegen-step-5
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol-rust-codegen
depends_on: [epic-bold-generated-protocol-rust-codegen-step-4]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] `pi_envelope`, `pi_envelope_in`, generic `AgentEnvelope`, and mesh HTTP wire DTOs are generated from the shared schema/IR.
- [x] `pi_forward.rs` and `mesh/types.rs` consume generated wire DTOs or re-export them rather than redefining them by hand.
- [x] Cross-PC `body` and app↔Pi `ct` remain opaque to the relay.
- [x] Rust parity tests validate relay/cross-PC fixtures and catch omitted generated variants.
- [x] `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass from `relay/`.

## Implementation

- Updated `tools/protocol-codegen/` so Rust generation emits the generated `CrossPcFrame` enum, `AgentEnvelope`, `PiEnvelopeFrame`, `PiEnvelopeInFrame`, and mesh HTTP DTOs (`MeshEnvelopeWire`, `MeshPostResponse`, `MeshGetResponse`, `MeshGetQuery`), then regenerated `relay/src/protocol/generated/`.
- `pi_forward.rs` now deserializes `pi_envelope` through generated cross-PC types and serializes `pi_envelope_in`/transport errors through generated types. `AgentEnvelope.body` stays `serde_json::Value`; body-level `session_id` remains endpoint-owned opaque data and is only forwarded.
- `mesh/types.rs` re-exports generated mesh wire DTOs while keeping decoded/internal `MeshEnvelope`, `MeshHeader`, and `MeshRecord` handwritten.
- Preserved peer-wide cross-PC forwarding with `forward_to_peer`; no relay-owned room target is added to `pi_envelope` or `pi_envelope_in` in this slice. Preserved `transport_error` as `_relay` with `re` and `body.type = "transport_error"`.
- Added `relay/tests/protocol_parity_test.rs` plus `protocol/fixtures/relay/mesh-http.jsonl`. Parity coverage deserializes cross-PC and mesh fixtures through generated Rust types, round-trips representative frames unchanged, and compares cross-PC fixture coverage to `CROSS_PC_TYPES` so omitted generated variants fail.
- Regen verdict: `--check` passed; deterministic double-run to two temp dirs had empty `diff -ru`; temp output vs `relay/src/protocol/generated` also had empty diff.
- Verification: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build` passed from `relay/`. `cargo test` ran 131 tests (76 lib, 3 integration, 13 mesh, 8 pi_forward, 10 presence, 2 protocol_parity, 19 rooms; doc tests 0).

## Risk

Medium. The main risk is over-typing `AgentEnvelope.body` or `session_id` and accidentally moving endpoint session semantics into the relay.

## Rollback

Revert cross-PC/mesh generated-type consumption and restore raw JSON parsing in `pi_forward.rs` plus handwritten wire DTOs in `mesh/types.rs`. Earlier generated outer/control/room types can remain.

## Review

Approved (2026-06-30) with generated-contract + opacity verification. Independently
re-ran: regen `--check` pass; determinism double-run byte-identical; committed
generated files match generator output (no hand-edits). Relay `cargo fmt --check`
clean; `cargo clippy -- -D warnings` clean; `cargo test` 131 passed / 0 failed
(76 lib + 3 integ + 13 mesh + 8 pi_forward + 10 presence + 2 protocol_parity +
19 rooms). Commit `f70ad5b` scoped to generated cross_pc.rs/mesh.rs + pi_forward.rs
+ mesh/types.rs + registry.rs + generator + parity test/fixtures + story .md.

Opacity preserved (the story's key risk): `AgentEnvelope.body` is
`serde_json::Value`; body-level `session_id` stays endpoint-owned opaque data
(forwarded only, never parsed by the relay). `transport_error` shape preserved
(`_relay` + `re` + `body.type = "transport_error"`). Mesh decoded/internal types
(`MeshEnvelope`/`MeshHeader`/`MeshRecord`) kept handwritten; only wire DTOs
generated. Peer-wide `forward_to_peer` preserved (room-targeting correctly
deferred to relay-opaque-targeting). Parity tests added
(`protocol_parity_test.rs` + `mesh-http.jsonl` fixture) deserialize cross-PC +
mesh fixtures through generated types, round-trip representative frames, and
compare coverage to `CROSS_PC_TYPES` so omitted variants fail. The
`forward_to_peer` registry addition is a legitimate supporting change.
