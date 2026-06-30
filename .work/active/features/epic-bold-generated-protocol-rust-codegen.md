---
id: epic-bold-generated-protocol-rust-codegen
kind: feature
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-generated-protocol
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Generated protocol — Rust serde codegen target

## Brief
Generate the Rust serde structs for `OuterEnvelope`, `RoomMeta`, and control
frames from the canonical schema, replacing the hand structs in
`relay/src/protocol/` and `rooms.rs`. The relay's private merge-patch
interpretation of `RoomMeta` (`rooms.rs:31-47`) derives from the same schema.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: consumer of `schema-source`. Relay keeps the `ct` payload opaque
  (it doesn't decode inner chat messages), so only the *relay-owned* types
  (outer envelope, room meta, control frames) are generated here.

## Foundation references
- Evidence: `relay/src/protocol/outer.rs:13`, `relay/src/rooms.rs:8`,
  `relay/src/handlers/peer.rs:135-186` (manual `hello.room_meta` JSON parse
  that should use a typed struct).

## Design decisions

- **Misroute check**: keep this item in the `[refactor]` lane. The Rust work replaces handwritten relay-owned serde structs with generated equivalents while preserving the live JSON wire shape, relay opacity, default-room compatibility, room-meta merge-patch behavior, and current cross-PC forwarding semantics. Canonical-session enforcement and cross-PC room targeting remain separate behavior-changing children.
- **Generator source**: Rust consumes the same canonical source chosen by `epic-bold-generated-protocol-schema-source`: JSON Schema 2020-12 plus the `x-remote-pi` manifest under `protocol/schema/`. The Rust backend should consume the normalized IR / deterministic catalog emitted by schema-source (`protocol` `list-types`) or the shared `tools/protocol-codegen` IR used by Dart, not a Rust-only schema mirror.
- **Step-1 schema dependency**: `epic-bold-generated-protocol-rust-codegen-step-1` depends on `epic-bold-generated-protocol-schema-source-step-5`. Rationale: the Rust generator should start from the completed schema-source generator handoff (`list-types` / normalized manifest and fixtures), not infer its own message catalog. Step 2 also depends on `epic-bold-generated-protocol-schema-source-step-3` because `OuterEnvelope`, relay control, room, and cross-PC schemas are introduced there.
- **Generated source posture**: generate committed Rust source under `relay/src/protocol/generated/` with a stale-check mode. Avoid `build.rs` generation so normal `cargo build` does not require Node/pnpm at compile time.
- **Serde compatibility profile**: preserve current permissive parsing unless the schema explicitly marks a frame strict. In particular, do not add `deny_unknown_fields` by default; current relay parsers ignore extra fields on known frames.
- **Opaque relay boundary**: generated Rust covers relay-owned frames only: outer envelope, room metadata, auth/control frames, cross-PC `pi_envelope`/`pi_envelope_in`, generic agent envelope shape, and mesh HTTP DTOs. It does not parse the inner app↔Pi `ct` payload, generic envelope `body`, or endpoint-owned `session_id` semantics.
- **Room patch IR requirement**: the normalized IR must represent optional-vs-nullable separately. `RoomMetaPatch.model` and `thinking` require `Option<Option<String>>`; `working` requires `Option<bool>` with no nullable clear state.
- **Patchbay posture**: the generated module consumes a neutral schema/IR and keeps relay session semantics out of Rust state. Future patchbay migration can replace the schema source or relay transport without unwinding relay-owned `session_id` assumptions.
- **Dispatch rationale**: direct-read only. The target was a bounded relay codegen design with explicit grounding files. This delegated sub-agent harness exposed file/search/shell tools but no usable subagent tool, so no exploratory or advisory sub-delegation was spawned despite the raised tier; advisory review remains a later autopilot responsibility.
- **Cycle check**: new stories form a backward-only dependency chain. Step 1 depends on `epic-bold-generated-protocol-schema-source-step-5`; step 2 depends on step 1 plus `epic-bold-generated-protocol-schema-source-step-3`; steps 3-5 depend only on the immediately previous Rust step. Schema-source stories do not depend on this feature, and the existing relay-typed-actor story depends on this feature rather than these child stories, so no frontmatter cycle is introduced.

## Code-smell scan findings

1. **Generated-contract gap** — `relay/src/protocol/outer.rs` hand-defines `OuterEnvelope` and parser limits while sibling surfaces move toward schema generation. High value: generated structs make Rust part of the same contract instead of a downstream mirror.
2. **Raw JSON control dispatch** — `relay/src/handlers/peer.rs` parses text into `serde_json::Value`, branches on `frame.get("type")`, and hand-peels `peers`, `room_id`, and `meta`. High value: generated control frames provide a typed fail-fast boundary for the future typed actor.
3. **Room metadata tri-state risk** — `relay/src/rooms.rs` encodes subtle merge-patch semantics in handwritten `RoomMetaPatch`. High value: schema/IR must make that semantic explicit so TS/Dart/Rust do not drift on `working` convergence.
4. **Cross-PC raw frame parsing** — `relay/src/handlers/pi_forward.rs` reads `to_pc` and `envelope` from raw JSON and forwards `body` opaquely by convention. Medium/high value: generated cross-PC structs can type the relay-owned wrapper while preserving opaque body semantics.
5. **Wire DTO spread** — `relay/src/auth/challenge.rs` and `relay/src/mesh/types.rs` define relay-owned JSON DTOs outside `relay/src/protocol/`. Medium value: generated modules can centralize wire DTOs while leaving crypto/storage internals handwritten.
6. **No project-specific refactor convention catalog** — `.agents/skills/refactor-conventions/` is absent; no convention-driven step was added beyond the default refactor-design lenses.

## Refactor Overview

The Rust relay currently has a small but important handwritten protocol surface: `OuterEnvelope`, auth/control frames, `RoomMeta`/`RoomMetaPatch`, cross-PC wrappers, and mesh HTTP DTOs. This design makes Rust a first-class consumer of the generated protocol without changing relay behavior. The codegen path is deliberately side-by-side first: generate committed serde types from the shared schema/IR, then replace one hand mirror at a time behind stable relay modules and tests.

The relay remains session-blind. `ct` stays a string whose size is bounded but never decoded. Cross-PC `AgentEnvelope.body` stays `serde_json::Value`; the relay verifies sibling authorization and forwards wrappers, but it does not parse app↔Pi inner chat messages or endpoint-owned `session_id`.

## Refactor Steps

### Step 1: Add the Rust generator backend over the shared protocol IR
**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contracts / missing abstraction  
**Files**: `protocol/scripts/list-types.ts`, `tools/protocol-codegen/` or `protocol/scripts/generate-rust.ts`, `relay/src/protocol/generated/`, `relay/src/protocol/mod.rs`  
**Story**: `epic-bold-generated-protocol-rust-codegen-step-1`

**Current State**:
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

**Target State**:
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

**Implementation Notes**:
- Consume schema-source's normalized manifest/catalog; fail if Rust-required metadata is missing instead of inventing a Rust-only mirror.
- Commit generated `.rs` files and provide a `--check` mode; do not make `cargo build` depend on Node/pnpm.
- Generated output must encode serde names, defaults, optional-vs-nullable, opaque JSON fields, and relay max-size metadata.

**Acceptance Criteria**:
- [ ] Rust codegen emits deterministic serde files under `relay/src/protocol/generated/`.
- [ ] The generator consumes the shared schema-source IR/manifest, not a Rust-only catalog.
- [ ] Stale generated Rust is caught by a check mode.
- [ ] Generated files have a do-not-edit header and stable module layout.

**Rollback**: Remove the Rust backend, generated skeleton, and check wiring; no runtime relay code depends on this step.

---

### Step 2: Generate `OuterEnvelope` and preserve the opaque payload parser
**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contracts / fail-fast boundary  
**Files**: `relay/src/protocol/generated/outer.rs`, `relay/src/protocol/outer.rs`, `relay/src/protocol/mod.rs`, `relay/src/handlers/peer.rs`  
**Story**: `epic-bold-generated-protocol-rust-codegen-step-2`

**Current State**:
```rust
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String, // base64 — never decoded here
}

pub fn parse_line(line: &str) -> Result<OuterEnvelope, ParseError> {
    parse_line_with_max(line, max_ct_bytes())
}
```

**Target State**:
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

**Implementation Notes**:
- Preserve `MAX_CT_ENV`, `DEFAULT_MAX_CT_MIB = 4`, `ParseError`, default `room = "main"`, and injected-limit tests.
- `ct` remains opaque; the relay estimates decoded size from base64 length only.
- Serialization output must remain compatible with current sender rewrite behavior in `handle_peer`.

**Acceptance Criteria**:
- [ ] `OuterEnvelope` serde fields are generated from the shared relay schema.
- [ ] `outer.rs` owns only parser limits/errors/re-exports, not a duplicate wire struct.
- [ ] Default-room and too-large tests still pass.
- [ ] No code decodes or inspects `ct`.

**Rollback**: Restore the handwritten `OuterEnvelope` definition in `outer.rs`.

---

### Step 3: Generate auth and relay control-frame serde types
**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / single source of truth / fail-fast boundary  
**Files**: `relay/src/protocol/generated/control.rs`, `relay/src/auth/challenge.rs`, `relay/src/handlers/peer.rs`, `relay/src/protocol/frame.rs` if introduced here  
**Story**: `epic-bold-generated-protocol-rust-codegen-step-3`

**Current State**:
```rust
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientAuthMsg {
    Hello { pubkey: String },
    Auth { sig: String },
}

match t {
    "subscribe_presence" => { /* raw peers parsing */ }
    "room_meta_update" => { /* raw meta parsing */ }
    "pi_envelope" => { /* cross-PC raw JSON path */ }
    _ => warn!(frame_type = %t, "unknown control frame type, dropping"),
}
```

**Target State**:
```rust
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

**Implementation Notes**:
- `auth/challenge.rs` still owns nonce generation and Ed25519 verification; only JSON frame shape is generated.
- Keep peer-list ceiling and rate-limit logic handwritten in the relay.
- `pi_envelope` remains a separate generated cross-PC family, not just another presence/rooms control frame.

**Acceptance Criteria**:
- [ ] Auth and relay control frame shapes are generated/re-exported from generated code.
- [ ] Known control frames parse into generated types before business logic.
- [ ] Peer-list ceilings, dedup, rate limiting, and warn/drop behavior are preserved.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Revert generated control/auth consumption and return to the raw JSON switch.

---

### Step 4: Generate `RoomMeta` / `RoomMetaPatch` and swap room state consumers
**Priority**: High  
**Risk**: High  
**Source Lens**: missing abstraction / merge-patch pattern drift  
**Files**: `relay/src/protocol/generated/room.rs`, `relay/src/rooms.rs`, `relay/src/peers/registry.rs`, `relay/src/handlers/peer.rs`  
**Story**: `epic-bold-generated-protocol-rust-codegen-step-4`

**Current State**:
```rust
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub working: Option<bool>,
}
```

**Target State**:
```rust
#[derive(Debug, Default, Clone, serde::Deserialize)]
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub working: Option<bool>,
}
```

`RoomMeta` and `RoomMetaPatch` fields are generated once; `rooms.rs` owns `RoomManager` and helper behavior such as `RoomMetaPatch::is_empty()` without redefining wire fields.

**Implementation Notes**:
- Preserve absent/null/bool merge-patch semantics exactly.
- `started_at` remains relay-local metadata; generation does not introduce relay-owned sessions.
- Keep `thinking` as an opaque string.

**Acceptance Criteria**:
- [ ] `RoomMeta` and `RoomMetaPatch` wire fields are generated.
- [ ] `rooms.rs`, `peers/registry.rs`, and `handlers/peer.rs` consume generated types/re-exports.
- [ ] Existing tests still prove `working` true/false/absent behavior.
- [ ] Room announcements and `rooms_check` JSON output remain compatible.

**Rollback**: Restore handwritten room structs in `rooms.rs`.

---

### Step 5: Generate cross-PC and mesh wire types, then add parity checks
**Priority**: High  
**Risk**: Medium  
**Source Lens**: duplicated wire structs / contract-test gap  
**Files**: `relay/src/protocol/generated/cross_pc.rs`, `relay/src/protocol/generated/mesh.rs`, `relay/src/handlers/pi_forward.rs`, `relay/src/mesh/types.rs`, relay protocol tests  
**Story**: `epic-bold-generated-protocol-rust-codegen-step-5`

**Current State**:
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
}
```

**Target State**:
```rust
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
```

Mesh HTTP JSON DTOs such as `MeshEnvelopeWire`, `PostResponse`, `GetResponse`, and `GetQuery` are generated or re-exported from `protocol/generated/mesh.rs`; decoded storage/internal types remain handwritten.

**Implementation Notes**:
- Preserve `_relay` `transport_error` envelope shape and peer-wide `forward_to_peer` until the canonical-session targeting item changes it deliberately.
- `AgentEnvelope.body` remains opaque `serde_json::Value`; do not parse `session_id` or inner app↔Pi messages.
- Add Rust parity tests over relay/cross-PC fixtures and generator stale checks.

**Acceptance Criteria**:
- [ ] Cross-PC wrappers, generic agent envelope shape, and mesh HTTP wire DTOs are generated.
- [ ] `pi_forward.rs` and `mesh/types.rs` consume generated wire DTOs/re-exports.
- [ ] Opaque `body` / `ct` relay boundaries are preserved.
- [ ] Relay/cross-PC fixture parity tests catch omitted generated variants.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo test` pass from `relay/`.

**Rollback**: Restore raw JSON parsing in `pi_forward.rs` and handwritten mesh wire DTOs. Earlier generated outer/control/room types can remain.

## Implementation Order

1. `epic-bold-generated-protocol-rust-codegen-step-1` — blocked on `epic-bold-generated-protocol-schema-source-step-5`.
2. `epic-bold-generated-protocol-rust-codegen-step-2` — also blocked on `epic-bold-generated-protocol-schema-source-step-3` for relay-owned schema definitions.
3. `epic-bold-generated-protocol-rust-codegen-step-3`.
4. `epic-bold-generated-protocol-rust-codegen-step-4`.
5. `epic-bold-generated-protocol-rust-codegen-step-5`.

## Atomic steps acknowledged

- Step 1 is strategically atomic with the schema-source generator handoff. If the shared IR lacks Rust-required metadata, implementation should extend schema-source rather than start a Rust-only catalog.
- Step 4 is the highest semantic risk because `RoomMetaPatch` tri-state behavior directly affects `working` convergence; rollback is isolated by consuming generated types through `rooms.rs` re-exports.
- Step 5 intentionally preserves peer-wide cross-PC forwarding; explicit room/session targeting is deferred to canonical-session relay targeting so this refactor remains behavior-preserving.

## Verification plan

For implementation stories, run from `relay/`:

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
```

Run the protocol generator stale check from the owning protocol package once the schema-source handoff exists (for example, `corepack pnpm --dir protocol generate:rust --check` or the final command documented by the implementation).

## Review — advanced to done (2026-06-30)

All 5 child steps `done` (outer envelope, auth/control, room, cross-PC/mesh —
all generated from the shared schema via `tools/protocol-codegen`, with the
generated-contract invariant verified clean + deterministic + no hand-edits at
each step). The relay's wire types are now generated, not hand-mirrored. Epic
complete.
