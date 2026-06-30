---
id: epic-bold-generated-protocol-rust-codegen-step-4
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol-rust-codegen
depends_on: [epic-bold-generated-protocol-rust-codegen-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Generate `RoomMeta` / `RoomMetaPatch` and swap room state consumers

**Priority**: High  
**Risk**: High  
**Source Lens**: missing abstraction / merge-patch pattern drift  
**Files**: `relay/src/protocol/generated/room.rs`, `relay/src/rooms.rs`, `relay/src/peers/registry.rs`, `relay/src/handlers/peer.rs`, room/registry tests

## Current State

Room metadata lives in `rooms.rs`, while `handle_peer` builds it by manually peeling `hello.room_meta`:

```rust
#[derive(Debug, Clone, serde::Serialize)]
pub struct RoomMeta {
    pub room_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<String>,
    pub working: bool,
    pub started_at: i64,
}

pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub working: Option<bool>,
}
```

## Target State

Room metadata and patch wire shapes are generated; `rooms.rs` owns only manager behavior and any local helper methods:

```rust
// relay/src/protocol/generated/room.rs
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RoomMeta {
    pub room_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<String>,
    #[serde(default)]
    pub working: bool,
    pub started_at: i64,
}

#[derive(Debug, Default, Clone, serde::Deserialize)]
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub working: Option<bool>,
}
```

## Implementation Notes

- Preserve merge-patch semantics exactly: absent means preserve; explicit `null` clears `model`/`thinking`; `working` is absent or bool only, never nullable.
- `started_at` remains relay-local connection metadata computed at auth time; generation describes the serialized field but does not invent session identity.
- If helper methods like `RoomMetaPatch::is_empty()` cannot be generated cleanly, implement them in a handwritten extension module without redefining the wire fields.
- Keep `thinking` an opaque string. The relay must not validate Pi model/thinking semantics.

## Acceptance Criteria

- [ ] `RoomMeta` and `RoomMetaPatch` wire fields are generated from schema.
- [ ] `rooms.rs`, `peers/registry.rs`, and `handlers/peer.rs` consume the generated types or a single re-export, not handwritten duplicate structs.
- [ ] Existing room-meta tests still prove `working` true/false/absent behavior.
- [ ] Room announcements and `rooms_check` JSON output remain compatible.
- [ ] Relay fmt/clippy/tests pass.

## Risk

High. `RoomMetaPatch` tri-state behavior is subtle and drives app UI convergence; a generated `Option<String>` where `Option<Option<String>>` is required would be a regression.

## Rollback

Restore the handwritten `RoomMeta`/`RoomMetaPatch` definitions in `rooms.rs` and revert consumers to those types. Generated room types can remain unused until corrected.

## Implementation

Generated `relay/src/protocol/generated/room.rs` from the shared relay-control schema via `tools/protocol-codegen`, expanding generated `RoomMeta` to the room snapshot fields (`room_id`, optional `name`/`cwd`/`model`/`thinking`, defaulted `working`, and relay-local `started_at`) and generating `RoomMetaPatch` with explicit nullable-string merge-patch decoding plus non-nullable `working` bool decoding. `rooms.rs` now re-exports the generated room types and owns only `RoomManager` plus the handwritten `RoomMetaPatch::is_empty()` helper; registry and peer-handler consumers continue through that single re-export rather than duplicate structs.

Regen-diff verdict: clean and deterministic. The canonical Rust generator `--check` passed. Two fresh generations to temp dirs were byte-identical (`diff -r` empty), and a fresh generation matched `relay/src/protocol/generated` exactly (`diff -r` empty), confirming no hand-edits under generated output.

Verification:

- `cargo fmt --check` — passed.
- `cargo clippy -- -D warnings` — passed.
- `cargo test` — passed: 126 tests total (72 lib unit, 3 integration, 13 mesh, 9 pi_forward, 10 presence, 19 rooms; 0 main/doc tests).
- `cargo build` — passed.

Deferred scope: `relay/src/protocol/generated/control.rs` still owns the generated control-frame-local `RoomMetaPatch` from Step 3 and was intentionally left untouched for the serialized `relay-typed-actor-control-handlers-step-5` wave. The live peer handler maps that generated control patch into the generated room patch re-export without changing observable merge-patch behavior.

## Review

Approved (2026-06-30) with generated-contract verification. Independently ran
the canonical regen-check from `protocol/`: `--check` pass (no drift);
determinism double-run byte-identical; committed `generated/room.rs` matches
fresh generator output exactly (no hand-edits). Relay: `cargo fmt --check`
clean; `cargo clippy -- -D warnings` clean; `cargo test` 126 passed / 0 failed
(72 lib + 3 integ + 13 mesh + 9 pi_forward + 10 presence + 19 rooms; +2 new
room-snapshot tests). Commit `54ca60b` scoped to generated/room.rs + rooms.rs +
generator + story .md; collision guard held (did NOT touch control.rs /
connection_actor / auth). `rooms.rs` re-exports generated room types and owns
only RoomManager + the is_empty() helper — registry/peer-handler consumers go
through the single re-export (cleaner than the Files list implied, not
scope-shrinking). Deferred scope (control.rs's own RoomMetaPatch awaits
control-handlers-step-5) is a legitimate sequencing decision, documented.
