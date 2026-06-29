---
id: epic-bold-generated-protocol-rust-codegen-step-4
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol-rust-codegen
depends_on: [epic-bold-generated-protocol-rust-codegen-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
