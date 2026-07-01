---
id: epic-bold-generated-protocol-rust-codegen-step-3
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol-rust-codegen
depends_on: [epic-bold-generated-protocol-rust-codegen-step-2]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 3: Generate auth and relay control-frame serde types

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / single source of truth / fail-fast boundary  
**Files**: `relay/src/protocol/generated/control.rs`, `relay/src/auth/challenge.rs`, `relay/src/handlers/peer.rs`, `relay/src/protocol/frame.rs` if introduced here, `relay/src/handlers/peer.rs` tests

## Current State

Auth and control frames are split between a small handwritten enum and a raw JSON switch:

```rust
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientAuthMsg {
    Hello { pubkey: String },
    Auth { sig: String },
}

if let Some(t) = frame.get("type").and_then(|v| v.as_str()) {
    match t {
        "subscribe_presence" => { /* peers parsed from serde_json::Value */ }
        "room_meta_update" => { /* meta parsed by hand */ }
        "pi_envelope" => { /* cross-PC raw JSON path */ }
        _ => warn!(peer = %peer_short, frame_type = %t, "unknown control frame type, dropping"),
    }
}
```

## Target State

Generated control/auth types are the parse boundary; handwritten code performs cryptographic checks and behavior:

```rust
// relay/src/protocol/generated/control.rs
#[derive(Debug, serde::Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientAuthMsg {
    Hello { pubkey: String, #[serde(default = "default_room")] room_id: String, room_meta: Option<HelloRoomMeta> },
    Auth { sig: String },
}

#[derive(Debug, serde::Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RelayControlFrame {
    SubscribePresence { #[serde(default)] peers: Vec<String> },
    UnsubscribePresence { #[serde(default)] peers: Vec<String> },
    PresenceCheck { #[serde(default)] peers: Vec<String> },
    SubscribeRooms { #[serde(default)] peers: Vec<String> },
    UnsubscribeRooms { #[serde(default)] peers: Vec<String> },
    RoomsCheck { #[serde(default)] peers: Vec<String> },
    RoomMetaUpdate { #[serde(default)] room_id: Option<String>, meta: RoomMetaPatch },
}
```

## Implementation Notes

- `auth/challenge.rs` should re-export or consume generated `ClientAuthMsg` / `ServerAuthMsg`; it still owns nonce generation and Ed25519 verification.
- Keep the current bounded peer-list rules (`MAX_CONTROL_FRAME_PEERS`) and rate limiter in handwritten relay logic; generation only owns the frame shape.
- Preserve current behavior for malformed control frames: warn/drop, no panic, no payload logging.
- Do not fold `pi_envelope` into `RelayControlFrame`; keep it as its own generated cross-PC family so the typed-actor feature can dispatch it separately.

## Acceptance Criteria

- [ ] Auth hello/auth/challenge wire structs are generated or re-exported from generated code.
- [ ] Presence/rooms/meta control-frame structs/enums are generated from schema, not handwritten string constants.
- [ ] `handle_peer` or a frame boundary can parse known control frames into generated types before business logic runs.
- [ ] Peer-list ceilings, check-rate costs, dedup, and warn/drop behavior are preserved.
- [ ] Relay fmt/clippy/tests pass.

## Risk

High. The control switch is broad; malformed-frame compatibility and room-meta patch semantics must not change accidentally.

## Rollback

Revert generated control-frame consumption and restore `auth/challenge.rs` plus `handle_peer` to the raw JSON control parsing path. Earlier generated outer-envelope work can remain.

## Implementation

Generated `relay/src/protocol/generated/control.rs` now owns the relay auth/challenge and post-auth control-frame serde boundary from the shared protocol schema catalog: `ClientAuthMsg`, `ServerAuthMsg`, `HelloRoomMeta`, typed presence/rooms control variants, typed `RoomMetaUpdate`, and the generated control-frame type registry. `auth/challenge.rs` consumes the generated auth types while retaining nonce generation and Ed25519 verification. The relay parses known control frames into generated types before handwritten behavior runs; `pi_envelope` remains outside `RelayControlFrame` on the cross-PC path.

Regen-diff verdict: clean and deterministic. I ran the Rust generator twice from the schema catalog and compared `git diff -- relay/src/protocol/generated` before/after each run; the generated diff was unchanged after both runs, with no hand edits to generated output.

Verification:

- `cargo fmt --check` — passed.
- `cargo clippy -- -D warnings` — passed.
- `cargo test` — passed: 122 tests total (68 lib unit, 3 integration, 13 mesh, 9 pi_forward, 10 presence, 19 rooms; 0 main/doc tests).
- `cargo build` — passed.

Deferred scope: none.

## Review

Approved (2026-06-30) with generated-contract verification. Independently ran
the canonical regen-check from `protocol/`:
- `--check` mode: pass (no drift between committed generated files and generator output).
- Determinism: two fresh regen runs to temp dirs are byte-identical (`diff -r` empty).
- No hand-edits: committed `relay/src/protocol/generated/control.rs` matches fresh generator output exactly.

Relay verification: `cargo fmt --check` clean; `cargo clippy -- -D warnings` clean;
`cargo test` 122 passed / 0 failed (68 lib + 3 integ + 13 mesh + 9 pi_forward + 10
presence + 19 rooms). Commit `c485dca` scoped to owned files (generated/control.rs,
auth/challenge.rs, handlers/{control,peer}.rs, generator). Acceptance criteria
verified: generated types own the auth/control serde boundary; `pi_envelope` kept
on the cross-PC path; `MAX_CONTROL_FRAME_PEERS=64` ceiling preserved; malformed/
unknown frames warn-and-drop (no panic, no payload logging).
