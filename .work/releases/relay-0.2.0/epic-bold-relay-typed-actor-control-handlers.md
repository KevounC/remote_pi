---
id: epic-bold-relay-typed-actor-control-handlers
kind: feature
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor
depends_on: [epic-bold-relay-typed-actor-frame-dispatch]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Relay typed actor — typed control handlers

## Brief
`presence.rs` and `rooms.rs` are near-duplicate subscription graphs
(`presence.rs:1-108` vs `rooms.rs:1-126`). Presence/rooms/`room_meta_update`
become typed handlers dispatched from the connection actor. The
`presence.rs`/`rooms.rs` duplication is resolved — either unified or kept
separate-but-typed per the design pass. Bad `peers` frames (which today become
an empty list, silently unsubscribing everything — `relay/src/handlers/peer.rs:56-68`)
fail-closed.

## Epic context
- Parent epic: `epic-bold-relay-typed-actor`
- Position: consumer of `frame-dispatch`.

## Foundation references
- Evidence: `relay/src/presence.rs:1-108`, `relay/src/rooms.rs:1-126`,
  `relay/src/handlers/peer.rs:56-68`, `:285-431`.

## Design decisions

- **Refactor lane retained**: this item stays in `[refactor]` because the primary change is structural: generated typed frames enter narrow relay handlers instead of raw JSON branches. The only intentional malformed-input behavior tightening is the briefed fail-closed `peers` boundary; happy-path wire shapes, routing, presence/rooms events, room metadata merge semantics, auth challenge behavior, and mesh membership status mapping remain unchanged.
- **Frame-dispatch dependency**: handler extraction assumes `epic-bold-relay-typed-actor-frame-dispatch` provides `ConnectionActor`, `ActorDispatch`, and generated `RelayControlFrame`/auth/mesh DTOs. Step 1 depends on that feature explicitly; later stories chain linearly.
- **Generated contract posture**: handlers consume generated Rust serde types from `epic-bold-generated-protocol-rust-codegen`. Implementers should adapt generated names through narrow re-exports rather than creating temporary handwritten mirrors.
- **Relay opacity**: `session_id` stays endpoint-owned and opaque. Room metadata may carry it for bootstrap, but control handlers do not route, authorize, log, index, or metrics-tag by it. Cross-PC `pi_envelope` body and app↔Pi `ct` remain opaque.
- **Presence/rooms unification**: resolve `presence.rs`/`rooms.rs` duplication by extracting a shared internal subscription graph while keeping `PresenceManager` and `RoomManager` public APIs stable. Presence-only offline timestamps stay in `PresenceManager`; room metadata stays in `RoomManager`/`PeerRegistry`.
- **Auth and mesh handlers**: auth challenge/hello bootstrap and mesh membership HTTP handlers are typed boundary handlers, but they are not endpoint session owners. Auth remains the pre-actor admission step; mesh membership remains Owner-signed HTTP state with the relay verifying/storing, not deciding membership.
- **Patchbay posture**: handler boundaries are neutral relay adapter seams over generated protocol types. They avoid baking Remote Pi session semantics into relay state, so patchbay can later replace the transport/schema source without unwinding relay-owned sessions.
- **Dispatch rationale**: direct-read design only. The target was a bounded relay slice with explicit grounding and no usable subagent tool in this delegated harness; further fanout would add coordination cost without improving the plan. Raised-tier requirement is satisfied by this openai-codex worker pass; advisory review remains an autopilot completion concern.
- **Cycle check**: `.work/bin/work-view --blocking` is absent in this checkout. A frontmatter graph check with the six proposed stories passed: step 1 depends on `epic-bold-relay-typed-actor-frame-dispatch`, and steps 2-6 depend only on the immediately previous control-handler story. No existing item points back to these new stories.

## Code-smell scan findings

1. **Code smell — god control switch**: `relay/src/handlers/peer.rs` mixes socket lifecycle, typed/outer frame classification, presence/rooms mutation, room-meta patching, Pi forwarding, rate limiting, dedup, metrics, and sink writes in one loop. High value: typed actor handlers isolate control-plane behavior from transport.
2. **Fail-fast gap — malformed peer lists**: `parse_bounded_control_peers` treats non-array `peers` as an empty list and drops non-string entries. High value: generated deserialization plus bounded validation prevents invalid frames from mutating subscription state.
3. **Generated-contract gap — auth hello bootstrap**: `auth/challenge.rs` parses only `pubkey`/`sig`, then `handle_peer` reparses `hello` as raw JSON for `room_id`/`room_meta`. High value: one typed auth result removes partial parsing and preserves defaults in one place.
4. **Missing abstraction — duplicated subscription graph**: `presence.rs` and `rooms.rs` duplicate replace/remove/remove-all/subscribers-of maps. High value: a shared `SubscriptionIndex` removes drift while leaving public manager APIs intact.
5. **Boundary drift — room metadata patching**: `room_meta_update` hand-builds `RoomMetaPatch` from raw JSON. High value: generated patch types make absent/null/bool semantics explicit and preserve `working` convergence behavior.
6. **Wire DTO spread — mesh membership**: `mesh/handler.rs` uses narrow good behavior but DTO shapes live in `mesh/types.rs`, outside the generated relay contract. Medium value: consuming generated DTOs completes the typed-handler boundary without changing membership authority.
7. **No project-specific refactor convention catalog**: `.agents/skills/refactor-conventions/` is absent; no convention-driven step was added beyond the default lenses.

## Refactor Overview

The frame-dispatch actor gives the relay a typed inbound frame boundary; this feature makes the control-plane code on the other side match that boundary. Auth bootstrap, presence subscriptions/checks, rooms subscriptions/checks, room metadata patching, and mesh membership HTTP DTOs become typed handlers over generated structs. The relay's behavior stays the same for valid clients: auth challenge-response, room registration defaults, presence backfill, rooms snapshots, dedup counters, `working` merge-patch semantics, Owner-signed mesh storage, and opaque routing are preserved.

The important structural payoff is that the connection loop stops being the place where every relay concern accumulates. It reads frames, invokes the actor, sends actor effects, and owns teardown. Handler modules own typed control behavior. Presence/rooms graph duplication is resolved through one internal subscription index, avoiding a broader registry split that belongs to the sibling `epic-bold-relay-typed-actor-registry-split`.

## Refactor Steps

### Step 1: Add the typed control-handler dispatch shell
**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / generated contracts / fail-fast boundary  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/control.rs`, `relay/src/handlers/peer.rs`, generated relay control frame types, `relay/src/metrics.rs`  
**Story**: `epic-bold-relay-typed-actor-control-handlers-step-1`

**Current State**:
```rust
if let Some(t) = frame.get("type").and_then(|v| v.as_str()) {
    match t {
        "subscribe_presence" => { /* raw peers parsing */ }
        "presence_check" => { /* limiter + response */ }
        "subscribe_rooms" => { /* raw peers parsing */ }
        "rooms_check" => { /* limiter + per-peer responses */ }
        "room_meta_update" => { /* raw meta parsing */ }
        "pi_envelope" => { /* cross-PC */ }
        _ => warn!(peer = %peer_short, frame_type = %t, "unknown control frame type, dropping"),
    }
    continue;
}
```

**Target State**:
```rust
impl ConnectionActor {
    pub async fn dispatch_control(&mut self, frame: RelayControlFrame) -> ActorDispatch {
        ControlHandlers::new(self).handle(frame).await
    }
}

impl ControlHandlers<'_> {
    async fn handle(&mut self, frame: RelayControlFrame) -> ActorDispatch {
        match frame {
            RelayControlFrame::SubscribePresence(frame) => self.subscribe_presence(frame).await,
            RelayControlFrame::UnsubscribePresence(frame) => self.unsubscribe_presence(frame).await,
            RelayControlFrame::PresenceCheck(frame) => self.presence_check(frame).await,
            RelayControlFrame::SubscribeRooms(frame) => self.subscribe_rooms(frame).await,
            RelayControlFrame::UnsubscribeRooms(frame) => self.unsubscribe_rooms(frame).await,
            RelayControlFrame::RoomsCheck(frame) => self.rooms_check(frame).await,
            RelayControlFrame::RoomMetaUpdate(frame) => self.room_meta_update(frame).await,
        }
    }
}
```

**Implementation Notes**:
- Consume the frame-dispatch actor and generated `RelayControlFrame`; do not add another handwritten control enum.
- Centralize peer-list bounds and fail-closed malformed `peers` behavior. Generated deserialization rejects non-array/non-string peer lists; the handler enforces `MAX_CONTROL_FRAME_PEERS`.
- Missing `peers` may default to `[]` only where the canonical schema says that is valid.

**Acceptance Criteria**:
- [ ] `ConnectionActor::dispatch_control` delegates to `relay/src/handlers/control.rs`.
- [ ] Control handlers receive generated typed frames, not `serde_json::Value`.
- [ ] Non-array or mixed-type `peers` frames fail before subscription mutation.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Revert `control.rs` and route generated frames through the prior raw branch logic temporarily.

---

### Step 2: Type the auth challenge and hello room bootstrap handler
**Priority**: High  
**Risk**: Medium  
**Source Lens**: fail-fast boundary / generated contracts  
**Files**: `relay/src/auth/challenge.rs`, `relay/src/handlers/peer.rs`, `relay/src/handlers/connection_actor.rs`, generated auth/hello room metadata types, `relay/src/rooms.rs`  
**Story**: `epic-bold-relay-typed-actor-control-handlers-step-2`

**Current State**:
```rust
let vk = parse_hello(&hello_text)?;
/* challenge + verify_auth */
let room_meta = {
    let hello: serde_json::Value = serde_json::from_str(&hello_text).unwrap_or(serde_json::Value::Null);
    let room_id = hello.get("room_id").and_then(|v| v.as_str()).unwrap_or("main").to_string();
    let room_meta_val = hello.get("room_meta");
    let working = room_meta_val
        .and_then(|m| m.get("working"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    RoomMeta { room_id, /* raw field peel */ working, started_at }
};
```

**Target State**:
```rust
pub struct AuthenticatedPeer {
    pub verifying_key: VerifyingKey,
    pub peer_id: String,
    pub room_meta: RoomMeta,
}

pub async fn authenticate_peer(/* stream, sink, clock */) -> Result<AuthenticatedPeer, AuthError> {
    let hello: ClientHello = read_typed_hello(/* ... */).await?;
    let vk = verifying_key_from_pubkey(&hello.pubkey)?;
    send_challenge(/* ... */).await?;
    verify_typed_auth(/* ... */).await?;
    Ok(AuthenticatedPeer {
        peer_id: B64.encode(vk.to_bytes()),
        verifying_key: vk,
        room_meta: hello.into_room_meta(/* now_ms */),
    })
}
```

**Implementation Notes**:
- Auth still owns nonce generation and Ed25519 verification; generation owns JSON shape.
- Preserve default `room_id = "main"`, missing metadata as absent, and missing `working = false`.
- Remove the post-auth raw `hello_text` parse from `handle_peer`.

**Acceptance Criteria**:
- [ ] Auth returns one typed `AuthenticatedPeer`/room bootstrap value.
- [ ] `handle_peer` does not reparse `hello_text` as raw JSON after auth.
- [ ] Existing auth failure modes and content-free logging remain.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Restore `parse_hello`/`verify_auth` plus current raw hello `RoomMeta` extraction.

---

### Step 3: Factor the duplicated presence/rooms subscription graph
**Priority**: High  
**Risk**: Low  
**Source Lens**: missing abstraction / code smell  
**Files**: `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/subscriptions.rs` or `relay/src/control/subscriptions.rs`, `relay/src/lib.rs`  
**Story**: `epic-bold-relay-typed-actor-control-handlers-step-3`

**Current State**:
```rust
struct Inner {
    subscribers_of: HashMap<String, HashSet<String>>,
    subscriptions_by: HashMap<String, HashSet<String>>,
    // presence-only: last_offline_ts
}

pub async fn subscribe(&self, subscriber: String, peers: Vec<String>) { /* replace full list */ }
pub async fn unsubscribe(&self, subscriber: &str, peers: Vec<String>) { /* remove subset */ }
pub async fn unsubscribe_all(&self, subscriber: &str) { /* cleanup */ }
pub async fn subscribers_of(&self, peer: &str) -> Vec<String> { /* lookup */ }
```

**Target State**:
```rust
pub(crate) struct SubscriptionIndex {
    subscribers_of: HashMap<String, HashSet<String>>,
    subscriptions_by: HashMap<String, HashSet<String>>,
}

impl SubscriptionIndex {
    pub fn replace(&mut self, subscriber: String, peers: Vec<String>) { /* existing semantics */ }
    pub fn remove(&mut self, subscriber: &str, peers: Vec<String>) { /* existing semantics */ }
    pub fn remove_all(&mut self, subscriber: &str) { /* existing semantics */ }
    pub fn subscribers_of(&self, peer: &str) -> Vec<String> { /* existing semantics */ }
}
```

**Implementation Notes**:
- Keep `PresenceManager` and `RoomManager` APIs stable.
- Presence retains `last_offline_ts`; rooms has only the shared graph.
- Preserve `subscribe(subscriber, [])` as clear-all.

**Acceptance Criteria**:
- [ ] One internal subscription graph backs both managers.
- [ ] Existing presence/rooms tests pass without public behavior changes.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Inline the shared graph back into `presence.rs` and `rooms.rs`.

---

### Step 4: Move presence and rooms control frames into typed actor handlers
**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / lifecycle ownership / missing abstraction  
**Files**: `relay/src/handlers/control.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/metrics.rs`  
**Story**: `epic-bold-relay-typed-actor-control-handlers-step-4`

**Current State**:
```rust
"presence_check" => {
    let Some(peers) = parse_bounded_control_peers(&frame, t, &peer_short) else { continue; };
    let cost = control_check_cost(&peers);
    if !control_check_limiter.allow(cost) { continue; }
    let states = presence.snapshot(&peers, |p| registry.is_online(p)).await;
    let resp = serde_json::json!({ "type": "presence", "states": states }).to_string();
    /* dedup + metrics + sink.send */
}

"rooms_check" => {
    for target_peer in &peers {
        let active_rooms = registry.rooms_of(target_peer);
        let resp = serde_json::json!({ "type": "rooms", "peer": target_peer, "rooms": active_rooms }).to_string();
        /* per-peer dedup + metrics + sink.send */
    }
}
```

**Target State**:
```rust
impl ControlHandlers<'_> {
    async fn subscribe_presence(&mut self, frame: SubscribePresenceFrame) -> ActorDispatch { /* typed peers + subscribe + backfill */ }
    async fn presence_check(&mut self, frame: PresenceCheckFrame) -> ActorDispatch { /* limiter + deduped presence response */ }
    async fn subscribe_rooms(&mut self, frame: SubscribeRoomsFrame) -> ActorDispatch { /* typed peers + subscribe */ }
    async fn rooms_check(&mut self, frame: RoomsCheckFrame) -> ActorDispatch { /* limiter + per-peer deduped rooms responses */ }
}
```

**Implementation Notes**:
- Preserve presence backfill, replacement/subset-unsubscribe semantics, shared check limiter, dedup slots, and metrics counters.
- `handle_peer` sends `ActorDispatch::Send`/`SendMany`; it does not shape presence/rooms JSON directly.

**Acceptance Criteria**:
- [ ] Presence and rooms subscribe/unsubscribe/check behavior lives in typed handlers.
- [ ] `peer.rs` no longer mutates `PresenceManager`/`RoomManager` for control frames.
- [ ] Dedup/limiter/metrics tests pass.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Move the presence/rooms branches back into `handle_peer`; keep `SubscriptionIndex` if it is already stable.

---

### Step 5: Move room metadata updates into a typed actor handler
**Priority**: High  
**Risk**: Medium  
**Source Lens**: fail-fast boundary / generated contracts / relay opacity  
**Files**: `relay/src/handlers/control.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, `relay/src/rooms.rs`, `relay/src/peers/registry.rs`, generated room metadata patch types  
**Story**: `epic-bold-relay-typed-actor-control-handlers-step-5`

**Current State**:
```rust
let target_room = frame.get("room_id").and_then(|v| v.as_str()).unwrap_or(&room_id).to_string();
let meta_obj = frame.get("meta").and_then(|v| v.as_object());
let model_patch = meta_obj.and_then(|m| m.get("model")).map(|v| v.as_str().map(String::from));
let thinking_patch = meta_obj.and_then(|m| m.get("thinking")).map(|v| v.as_str().map(String::from));
let session_id_patch = meta_obj.and_then(|m| m.get("session_id")).map(|v| v.as_str().map(String::from));
let working_patch = meta_obj.and_then(|m| m.get("working")).and_then(|v| v.as_bool());
let patch = RoomMetaPatch { model: model_patch, thinking: thinking_patch, session_id: session_id_patch, working: working_patch };
```

**Target State**:
```rust
async fn room_meta_update(&mut self, frame: RoomMetaUpdateFrame) -> ActorDispatch {
    let target_room = frame.room_id.unwrap_or_else(|| self.actor.room_id.clone());
    if !self.actor.registry.update_room_meta(&self.actor.peer_id, &target_room, frame.meta).await {
        warn!(peer = %self.actor.peer_short, room = %target_room,
            "room_meta_update for unknown (peer, room), dropping");
    }
    ActorDispatch::Continue
}
```

**Implementation Notes**:
- Consume generated `RoomMetaPatch` with `Option<Option<String>>` for nullable strings and `Option<bool>` for `working`.
- Preserve absent/null/bool merge-patch behavior exactly.
- Keep `session_id` opaque; do not route by it.

**Acceptance Criteria**:
- [ ] `room_meta_update` is typed-handler code, not raw field peeling in `peer.rs`.
- [ ] Tests cover `working` true/false/absent and string null clears.
- [ ] Malformed `meta` fails at decode rather than becoming an empty patch.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Restore the raw `room_meta_update` branch and handwritten patch construction.

---

### Step 6: Consume generated mesh-membership DTOs at the HTTP handler boundary
**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: generated contracts / fail-fast boundary  
**Files**: `relay/src/mesh/handler.rs`, `relay/src/mesh/types.rs`, generated mesh DTO module, `relay/src/mesh/verify.rs`, relay mesh tests  
**Story**: `epic-bold-relay-typed-actor-control-handlers-step-6`

**Current State**:
```rust
let wire: MeshEnvelopeWire = serde_json::from_slice(&body)
    .map_err(|e| MeshHttpError::BadRequest(format!("invalid json: {e}")))?;
let env = decode_wire(&wire).map_err(|e| MeshHttpError::BadRequest(format!("decode: {e}")))?;
let header = verify_envelope(&env)?;
```

**Target State**:
```rust
use crate::protocol::generated::mesh::{GetMeshQuery, GetMeshResponse, MeshEnvelopeWire, PostMeshResponse};

pub async fn post_mesh(/* ... */) -> Result<(StatusCode, Json<PostMeshResponse>), MeshHttpError> {
    reject_too_large(body.len())?;
    let wire: MeshEnvelopeWire = serde_json::from_slice(&body).map_err(MeshHttpError::invalid_json)?;
    let env = decode_wire(&wire).map_err(MeshHttpError::bad_wire)?;
    let header = verify_owner_envelope(&env, &url_hash)?;
    store_newer_version(/* ... */)
}
```

**Implementation Notes**:
- Preserve body cap, Owner signature verification, URL hash match, monotonic version rejection, 304 behavior, and status mapping.
- The relay verifies and stores Owner-signed membership; it still does not decide membership.
- Coordinate with generated Rust mesh DTO names rather than inventing Rust-only schema names.

**Acceptance Criteria**:
- [ ] Mesh HTTP DTOs are generated or re-exported from generated code.
- [ ] `mesh/handler.rs` keeps HTTP status and persistence behavior unchanged.
- [ ] Mesh tests prove signature, hash, conflict, not-modified, and body-cap behavior.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Restore handwritten DTO definitions in `relay/src/mesh/types.rs` and the existing handler imports.

## Implementation Order

1. `epic-bold-relay-typed-actor-control-handlers-step-1` (depends on `epic-bold-relay-typed-actor-frame-dispatch`)
2. `epic-bold-relay-typed-actor-control-handlers-step-2`
3. `epic-bold-relay-typed-actor-control-handlers-step-3`
4. `epic-bold-relay-typed-actor-control-handlers-step-4`
5. `epic-bold-relay-typed-actor-control-handlers-step-5`
6. `epic-bold-relay-typed-actor-control-handlers-step-6`

## Atomic steps acknowledged

- Step 1 is coupled to the frame-dispatch actor shape. If generated enum names differ, add local re-exports/adapters at the protocol boundary rather than hand-writing a parallel control enum.
- Step 2 is connection-critical but rollback-isolated before registry registration; auth challenge semantics must remain exact.
- Step 5 is semantically sensitive because `RoomMetaPatch.working` drives mobile working-state convergence. Treat its tests as required, not optional.
- Step 6 depends on generated mesh DTOs from the Rust codegen story; if they are not available yet, implementers should wait or extend that codegen story rather than inventing a temporary mirror.

## Verification plan

For implementation stories, run from `relay/`:

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
```

Targeted tests should cover malformed peer-list fail-closed behavior, auth hello defaults, subscription graph replacement/removal, presence/rooms dedup and check limiter behavior, room metadata merge-patch semantics, and mesh HTTP status compatibility.

## Review — advanced to done (2026-06-30)

All 6 child steps `done` (control/auth handlers, presence/rooms dedup, room-meta
typed actor, mesh HTTP boundary — all consuming generated protocol types with
the generated-contract invariant held at each generated step). The relay's
control-frame and mesh-membership handling is now typed-actor + generated-DTO
driven. Epic complete.
