---
id: epic-bold-relay-typed-actor-control-handlers-step-5
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-control-handlers
depends_on: [epic-bold-relay-typed-actor-control-handlers-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 5: Move room metadata updates into a typed actor handler

**Priority**: High  
**Risk**: Medium  
**Source Lens**: fail-fast boundary / generated contracts / relay opacity  
**Files**: `relay/src/handlers/control.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, `relay/src/rooms.rs`, `relay/src/peers/registry.rs`, generated room metadata patch types

## Current State

`room_meta_update` is hand-parsed in the raw switch and constructs `RoomMetaPatch` from loosely inspected JSON:

```rust
let target_room = frame
    .get("room_id")
    .and_then(|v| v.as_str())
    .unwrap_or(&room_id)
    .to_string();
let meta_obj = frame.get("meta").and_then(|v| v.as_object());
let model_patch = meta_obj
    .and_then(|m| m.get("model"))
    .map(|v| v.as_str().map(String::from));
let thinking_patch = meta_obj
    .and_then(|m| m.get("thinking"))
    .map(|v| v.as_str().map(String::from));
let session_id_patch = meta_obj
    .and_then(|m| m.get("session_id"))
    .map(|v| v.as_str().map(String::from));
let working_patch = meta_obj
    .and_then(|m| m.get("working"))
    .and_then(|v| v.as_bool());
let patch = RoomMetaPatch { model: model_patch, thinking: thinking_patch, session_id: session_id_patch, working: working_patch };
registry.update_room_meta(&peer_id, &target_room, patch).await;
```

Malformed `meta` silently becomes an empty patch; non-bool `working` is ignored.

## Target State

Generated control frame types carry the merge-patch shape into a narrow handler:

```rust
impl ControlHandlers<'_> {
    async fn room_meta_update(&mut self, frame: RoomMetaUpdateFrame) -> ActorDispatch {
        let target_room = frame.room_id.unwrap_or_else(|| self.actor.room_id.clone());
        if !self.actor.registry
            .update_room_meta(&self.actor.peer_id, &target_room, frame.meta)
            .await
        {
            warn!(peer = %self.actor.peer_short, room = %target_room,
                "room_meta_update for unknown (peer, room), dropping");
        }
        ActorDispatch::Continue
    }
}
```

`RoomMetaPatch` remains the sole place encoding absent/null/bool semantics:

```rust
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub session_id: Option<Option<String>>,
    pub working: Option<bool>,
}
```

## Implementation Notes

- Consume generated `RoomMetaUpdateFrame` and `RoomMetaPatch`; `rooms.rs` may re-export helper behavior such as `is_empty()` but must not redefine wire fields.
- Preserve merge-patch semantics: absent leaves unchanged; nullable string `null` clears; `working` changes only with a present boolean.
- Keep `session_id` opaque metadata for bootstrap. Do not route, index, log, or metrics-tag by `session_id`.
- Preserve unknown-room warn/drop behavior without logging metadata values.

## Acceptance Criteria

- [ ] `room_meta_update` is handled by a typed actor handler, not raw JSON field peeling in `peer.rs`.
- [ ] Tests prove `working: true`, `working: false`, absent `working`, string clears, and empty patch behavior remain unchanged.
- [ ] A malformed `meta` shape fails at the generated decode boundary rather than silently producing an empty patch.
- [ ] The relay continues to treat `session_id` as opaque room metadata only.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Medium. The tri-state patch semantics are subtle and drive mobile working-state convergence.

## Rollback

Restore the raw `room_meta_update` branch and handwritten `RoomMetaPatch` construction. Keep earlier presence/rooms handler extraction if unaffected.

## Implementation

- Typed handler approach: generated `RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame)` now carries the generated `RoomMetaPatch` from `relay/src/protocol/generated/room.rs` into `ControlHandlers::room_meta_update`; `peer.rs` only decodes typed control frames and dispatches actor effects.
- Merge-patch semantics preserved: `RoomMetaPatch` keeps absent/null/string tri-state for `model`, `thinking`, and `session_id`; `working` changes only when a boolean is present; empty patches still acknowledge existing rooms without broadcasting.
- Malformed-meta fail-fast: generated `RoomMetaPatch` now deserializes via a map-only visitor, so non-object `meta`, `working: null`, duplicate fields, and unknown fields fail at decode instead of becoming empty patches.
- `session_id` remains opaque room metadata: it is stored and included in room metadata snapshots/updates when present, but is not used for routing, indexing, logs, or metrics.
- Regen verdict: touched `tools/protocol-codegen/`, regenerated `relay/src/protocol/generated/*`, `--check` passed, and deterministic double-run temp output matched both temp dirs and the committed generated directory.
- Tests: `cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo build` passed from `relay/` (`cargo test`: 78 lib + 3 integration + 13 mesh + 9 pi_forward + 10 presence + 19 rooms = 132 tests).

## Review

Approved (2026-06-30) with generated-contract + merge-patch verification.
Independently re-ran: regen `--check` pass; determinism double-run byte-identical;
committed generated files match generator output (no hand-edits). Relay
`cargo fmt --check` clean; `cargo clippy -- -D warnings` clean; `cargo test`
132 passed / 0 failed (78 lib + 3 integ + 13 mesh + 9 pi_forward + 10 presence +
19 rooms; +6 new merge-patch/registry tests). Commit `7d6e8ff` reconciled the two
`RoomMetaPatch` sources (generated/control.rs + generated/room.rs) via the
generator — `ControlHandlers::room_meta_update` now consumes the generated
`RoomMetaUpdateFrame`; `peer.rs` only decodes typed control frames + dispatches.

Merge-patch tri-state verified directly in tests: `working_true_patch_broadcasts_true`,
`working_false_patch_broadcasts_false`, `nullable_string_patch_clears_session_id_metadata`,
`empty_patch_is_acknowledged_without_broadcast`. Malformed-meta fail-fast confirmed:
generated `RoomMetaPatch` deserializes via a map-only visitor (non-object meta,
`working:null`, duplicate/unknown fields fail at decode, not silent empty patch).
`session_id` remains opaque room metadata (stored/snapshotted, not routed/indexed/
logged). Reconciling the step-3 control.rs `RoomMetaPatch` with step-4's room.rs
one was the intended resolution — clean.
