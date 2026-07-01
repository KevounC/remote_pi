---
id: epic-bold-generated-protocol-rust-codegen-step-1
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol-rust-codegen
depends_on: [epic-bold-generated-protocol-schema-source-step-5]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Add the Rust generator backend over the shared protocol IR

**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contracts / missing abstraction  
**Files**: `protocol/scripts/list-types.ts`, `tools/protocol-codegen/` or `protocol/scripts/generate-rust.ts`, `relay/src/protocol/generated/`, `relay/src/protocol/mod.rs`, `relay/Cargo.toml` only if a Rust-side check dependency is unavoidable

## Current State

Rust protocol boundary structs are handwritten in relay modules:

```rust
// relay/src/protocol/outer.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String,
}
```

There is no generator target that consumes the schema-source manifest or the Dart-codegen normalized IR.

## Target State

A deterministic Rust backend consumes the same normalized schema/IR catalog used by Dart and emits committed serde source under `relay/src/protocol/generated/`:

```rust
// relay/src/protocol/generated/mod.rs
// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
pub mod outer;
pub mod room;
pub mod control;
pub mod cross_pc;
pub mod mesh;
```

Generator input requirements are explicit: discriminator, transport family, Rust type name, serde rename, optional-vs-nullable field shape, defaults, opaque JSON fields, and relay-only max-size metadata.

## Implementation Notes

- Consume the schema-source handoff (`corepack pnpm --dir protocol list-types`) or its normalized JSON output; do not parse ad hoc Rust-only message catalogs.
- Prefer committed generated `.rs` files plus a `--check` mode over `build.rs` generation. `cargo build` must not require Node/pnpm to be available at compile time.
- Keep generated Rust code free of `deny_unknown_fields` in the compat profile unless schema-source explicitly marks a frame strict; current relay parsers tolerate extra fields.
- Record generator metadata for `Option<T>` vs `Option<Option<T>>` because room-meta merge-patch semantics depend on that distinction.
- Do not switch runtime relay consumers in this step beyond adding imports/tests for the generated module skeleton.

## Acceptance Criteria

- [ ] A Rust codegen command emits deterministic serde files under `relay/src/protocol/generated/`.
- [ ] The generator consumes the shared schema-source normalized IR / manifest, not a Rust-only mirror.
- [ ] A check mode fails if committed generated Rust is stale.
- [ ] Generated files include a do-not-edit header and stable module layout for later steps.
- [ ] `corepack pnpm --dir protocol list-types` and the Rust generator check pass.

## Risk

Medium. The strategic risk is accidentally creating a second Rust-specific protocol source; the implementation must fail if the shared IR lacks information the Rust backend needs.

## Rollback

Remove the Rust generator backend, generated module skeleton, and check wiring. No runtime relay behavior depends on this step.

## Implementation notes
- Files changed: `tools/protocol-codegen/bin/protocol-codegen.mjs`, `protocol/package.json`, `relay/src/protocol/mod.rs`, `relay/src/protocol/generated/mod.rs`, `relay/src/protocol/generated/outer.rs`, `relay/src/protocol/generated/room.rs`, `relay/src/protocol/generated/control.rs`, `relay/src/protocol/generated/cross_pc.rs`, `relay/src/protocol/generated/mesh.rs`.
- Tests added: none; this story adds the generator backend and committed generated skeleton for later runtime adoption stories.
- Discrepancies from design: generated relay-owned Rust modules are side-by-side and intentionally not consumed by relay runtime code yet, except for adding the generated module to `protocol::mod`. The Step 1 catalog still lacks full per-field Rust metadata for every frame, so the backend emits stable relay-owned skeletons and fails staleness via `generate:rust:check` rather than switching handwritten consumers.
- Adjacent issues parked: none.
- Verification: `corepack pnpm --dir protocol generate:rust`, `corepack pnpm --dir protocol generate:rust:check`, `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` all passed from `relay/` (with pnpm warning about unreadable `/home/agent/.npmrc`, non-fatal).

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Inspected implementation commit `3d35248`; no `build.rs` exists, `cargo build`/`cargo test` do not require Node, generated Rust files are committed under `relay/src/protocol/generated/`, and `protocol/package.json` provides a stale-check path. `RoomMetaPatch` preserves tri-state nullable fields with `Option<Option<String>>` for nullable string patches and `Option<bool>` for non-nullable `working`; generated cross-PC/body fields remain `serde_json::Value`/opaque and do not parse inner `ct` or `session_id`. Verification run: `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store list-types`, `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store generate:rust:check`, and from `relay/` `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.

