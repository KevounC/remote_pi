---
id: epic-bold-generated-protocol-rust-codegen-step-2
kind: story
stage: review
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol-rust-codegen
depends_on: [epic-bold-generated-protocol-rust-codegen-step-1, epic-bold-generated-protocol-schema-source-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Generate `OuterEnvelope` and preserve the opaque payload parser

**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contracts / fail-fast boundary  
**Files**: `relay/src/protocol/generated/outer.rs`, `relay/src/protocol/outer.rs`, `relay/src/protocol/mod.rs`, `relay/src/handlers/peer.rs`, `relay/src/protocol/outer.rs` tests

## Current State

`OuterEnvelope` is handwritten and owns both wire fields and parser limits:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String, // base64 — nunca decodificado aqui
}

pub fn parse_line(line: &str) -> Result<OuterEnvelope, ParseError> {
    parse_line_with_max(line, max_ct_bytes())
}
```

## Target State

The wire struct is generated; the handwritten module becomes a thin relay-owned parser facade for size checks and compatibility errors:

```rust
// relay/src/protocol/generated/outer.rs
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String,
}

// relay/src/protocol/outer.rs
pub use crate::protocol::generated::outer::OuterEnvelope;

pub fn parse_line(line: &str) -> Result<OuterEnvelope, ParseError> {
    let env: OuterEnvelope = serde_json::from_str(line)?;
    reject_if_ct_too_large(&env.ct, max_ct_bytes())?;
    Ok(env)
}
```

## Implementation Notes

- Preserve current `MAX_CT_ENV`, `DEFAULT_MAX_CT_MIB = 4`, `ParseError`, and injected-size tests.
- Preserve the compatibility default: absent `room` becomes `"main"` until a later behavior-changing targeting feature removes or gates it.
- Treat `ct` as an opaque base64 string. The relay only estimates size from string length and never decodes inner chat content.
- Keep serialization output compatible with current relay rewrites in `handle_peer`.

## Acceptance Criteria

- [ ] `OuterEnvelope`'s serde struct is generated from the shared relay schema.
- [ ] `relay/src/protocol/outer.rs` no longer hand-defines the wire struct; it only owns parser limits/errors/re-exports.
- [ ] Existing outer envelope tests still pass, including default room and too-large rejection.
- [ ] No relay code decodes or inspects `ct`.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and targeted relay tests pass from `relay/`.

## Risk

Medium. Changing no-`room` defaults or `ct` size behavior would be observable to existing clients.

## Rollback

Revert the generated `OuterEnvelope` consumption and restore the handwritten struct in `relay/src/protocol/outer.rs`. Parser constants/tests can remain if unchanged.

## Implementation notes
- Files changed: `relay/src/protocol/outer.rs`.
- Tests added/updated: updated the outer-envelope parser test to assert missing `room` defaults to `main` through the generated struct; existing opaque-`ct`, limit, invalid JSON, and explicit-room tests remain.
- Discrepancies from design: none; the handwritten module now re-exports the generated `OuterEnvelope` and owns only parser limits/errors/tests.
- Adjacent issues parked: none.
- Verification: from `relay/`, `cargo fmt --check`, `cargo test protocol::outer`, `cargo clippy -- -D warnings`, and full `cargo test` all passed.
