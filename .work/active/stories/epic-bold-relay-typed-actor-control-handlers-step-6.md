---
id: epic-bold-relay-typed-actor-control-handlers-step-6
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-control-handlers
depends_on: [epic-bold-relay-typed-actor-control-handlers-step-5]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 6: Consume generated mesh-membership DTOs at the HTTP handler boundary

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: generated contracts / fail-fast boundary  
**Files**: `relay/src/mesh/handler.rs`, `relay/src/mesh/types.rs`, generated mesh DTO module, `relay/src/mesh/verify.rs`, relay mesh tests

## Current State

Mesh HTTP handlers parse handwritten DTOs from `mesh/types.rs` and then run verification/storage behavior:

```rust
let wire: MeshEnvelopeWire = serde_json::from_slice(&body)
    .map_err(|e| MeshHttpError::BadRequest(format!("invalid json: {e}")))?;
let env = decode_wire(&wire).map_err(|e| MeshHttpError::BadRequest(format!("decode: {e}")))?;

let header = verify_envelope(&env).map_err(|e| match e {
    VerifyError::SigFailed => MeshHttpError::Forbidden("sig_invalid".into()),
    /* ... */
})?;
```

The behavior is narrow and good, but the wire DTO names are still another handwritten relay mirror.

## Target State

Keep `mesh/handler.rs` as the HTTP adapter, but consume generated DTOs/re-exports for request/response shape:

```rust
use crate::protocol::generated::mesh::{GetMeshQuery, GetMeshResponse, MeshEnvelopeWire, PostMeshResponse};

pub async fn post_mesh(
    State(store): State<Arc<MeshStore>>,
    Path(url_hash): Path<String>,
    body: axum::body::Bytes,
) -> Result<(StatusCode, Json<PostMeshResponse>), MeshHttpError> {
    reject_too_large(body.len())?;
    let wire: MeshEnvelopeWire = serde_json::from_slice(&body)
        .map_err(MeshHttpError::invalid_json)?;
    let env = decode_wire(&wire).map_err(MeshHttpError::bad_wire)?;
    let header = verify_owner_envelope(&env, &url_hash)?;
    store_newer_version(store, header, env).map(Json)
}
```

`mesh/types.rs` either re-exports generated DTOs for compatibility or shrinks to decoded internal structs only.

## Implementation Notes

- This is a boundary refactor only. Preserve body cap, Owner signature verification, URL hash match, version monotonicity, 304 behavior, and HTTP status mapping.
- Do not move mesh membership authority into the relay. The Owner-signed blob remains authoritative; the relay verifies and stores it.
- Keep raw blobs/signatures out of logs.
- Coordinate with `epic-bold-generated-protocol-rust-codegen-step-5`, which emits the generated mesh DTOs; do not create Rust-only schema names if generated names differ.

## Acceptance Criteria

- [x] Mesh HTTP request/response DTOs are generated or re-exported from generated code.
- [x] `mesh/handler.rs` still owns HTTP status mapping and `MeshStore` persistence behavior.
- [x] Signature verification, owner hash matching, monotonic-version rejection, and `since`/304 behavior remain unchanged.
- [x] No logs include raw mesh blobs or signatures.
- [x] Relay fmt/clippy/tests pass.

## Implementation

- `relay/src/mesh/handler.rs` now imports `MeshEnvelopeWire`, `MeshPostResponse`, `MeshGetResponse`, and `MeshGetQuery` directly from `crate::protocol::generated::mesh` at the HTTP adapter boundary.
- `relay/src/mesh/types.rs` keeps only decoded/internal mesh structs plus exact-name generated DTO re-exports; no Rust-only aliases were added.
- Preserved body cap, Owner signature verification, URL hash matching, monotonic version rejection, `since`/304 behavior, and existing HTTP status strings/codes.
- Mesh tests now post and decode generated DTO structs while keeping black-box compatibility coverage for signature verification, hash mismatch, stale/same versions, and `since`/304.
- Logging remains unchanged and does not include raw blobs or signatures.
- Generator was not changed; regen not applicable.
- Verification: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build` from `relay/` passed (131 tests).

## Risk

Medium. HTTP compatibility must remain exact even though DTO ownership changes.

## Rollback

Restore handwritten DTO definitions in `relay/src/mesh/types.rs` and keep the existing handler logic. This does not affect the WebSocket actor stories.

## Review

Approved (2026-06-30). Independently re-ran: relay `cargo fmt --check` clean;
`cargo clippy -- -D warnings` clean; `cargo test` 131 passed / 0 failed. Commit
`187fac7` scoped to mesh/handler.rs + mesh/types.rs + mesh/mod.rs + mesh_test.rs
+ story .md; NO generated files touched (boundary refactor consuming existing
generated DTOs — regen N/A, confirmed). HTTP-compatibility invariants verified:
body cap, Owner sig verification, URL hash match, monotonic-version rejection,
since/304 behavior, HTTP status strings/codes all preserved (mesh_test covers
sig/hash/version/304). No raw blob/signature logging added (privacy preserved).
`mesh/types.rs` keeps only decoded/internal structs + exact-name re-exports
(no Rust-only aliases).
