---
id: epic-bold-relay-typed-actor-frame-dispatch
kind: feature
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Relay typed actor — typed-frame dispatch (riskiest — design first)

## Brief
Decode incoming frames into generated typed enums (from
`epic-bold-generated-protocol`) and dispatch via a connection actor loop that
replaces the raw-JSON switch in `handle_peer` (`relay/src/handlers/peer.rs:265-431`,
branching on `frame.get("type").as_str()`). The typed-frame decode + dispatch
shape is what the registry split and handler extraction both depend on, so it
lands first.

## Epic context
- Parent epic: `epic-bold-relay-typed-actor`
- Position: riskiest child — the dispatch shape is what the rest hangs on.
  Design FIRST. Depends on the generated-protocol epic for typed frames.

## Foundation references
- Evidence: `relay/src/handlers/peer.rs:118-431` (god loop), `:135-186`
  (manual `hello.room_meta` JSON parse).

<!-- /agile-workflow:refactor-design pins the actor + typed dispatch shape. -->

## Design decisions

- **Typed boundary source**: the relay dispatch layer consumes generated Rust serde types emitted from the JSON Schema 2020-12 protocol source chosen by `epic-bold-generated-protocol-schema-source`. This feature does not define the schema language or create a second handwritten protocol mirror.
- **Implementation prerequisite**: step 1 depends on `epic-bold-generated-protocol-rust-codegen` so implementers do not invent temporary hand-maintained frame structs. The feature can be designed now; implementation waits for generated Rust relay-owned frame types.
- **Behavior-preservation boundary**: this is a structural refactor. It preserves the live wire shape, including no-`type` app↔Pi outer envelopes, current `pi_envelope` transport-error shapes, current peer-wide cross-PC fanout until the canonical-session targeting sibling changes it, and current presence/rooms semantics.
- **Relay opacity**: the actor dispatches relay-owned frames only. It never parses app↔Pi `ct`, generic envelope `body`, or endpoint-owned `session_id`; the relay continues routing by `(peer, room)` and current cross-PC `to_pc` until the targeting child adds explicit room targeting.
- **Handler split boundary**: this feature creates the typed actor and frame dispatch shape. It intentionally leaves `PeerRegistry` splitting and presence/rooms manager unification to sibling features.
- **Patchbay posture**: the actor consumes neutral generated protocol types and keeps endpoint session semantics out of relay state, so future patchbay migration can replace the generated source/transport without unwinding relay-owned session assumptions.
- **Dispatch rationale**: direct-read only. The target was a bounded relay module with explicit grounding files; this delegated sub-agent harness exposed read/write/search shell tools but no `subagent` or peer-review tool, so no exploratory or advisory sub-agent was spawned.
- **Cycle check**: new stories form a linear chain. Step 1 has the external prerequisite `epic-bold-generated-protocol-rust-codegen`; each later step depends only on the immediately previous step. Existing downstream features depend on this feature, not on these stories. No frontmatter cycle is introduced.

## Refactor Overview

`relay/src/handlers/peer.rs` is currently one authenticated WebSocket owner that also acts as parser, raw JSON switch, control-plane router, cross-PC forwarder, outer-envelope rewriter, dedup store, rate limiter, heartbeat loop, and teardown owner. The high-value refactor is to invert that shape: the socket loop remains the transport/lifecycle adapter, and an authenticated `ConnectionActor` receives generated typed relay frames and dispatches by Rust enum variant.

The plan deliberately avoids changing relay responsibilities. The relay keeps forwarding app↔Pi payloads opaquely, keeps mesh authorization in `MeshAuthCache`, keeps `PeerRegistry` APIs until the registry-split child owns them, and keeps presence/rooms semantics until the control-handlers child owns that cleanup.

## Refactor Steps

### Step 1: Introduce the typed relay frame decode boundary
**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / generated contracts / fail-fast boundary  
**Files**: `relay/src/protocol/mod.rs`, `relay/src/protocol/frame.rs`, generated Rust protocol module from `epic-bold-generated-protocol-rust-codegen`, `relay/src/protocol/outer.rs`  
**Story**: `epic-bold-relay-typed-actor-frame-dispatch-step-1`

**Current State**:
```rust
let frame: serde_json::Value = match serde_json::from_str(&text) {
    Ok(v) => v,
    Err(e) => {
        warn!(peer = %peer_short, err = %e, "invalid json, dropping");
        continue;
    }
};

if let Some(t) = frame.get("type").and_then(|v| v.as_str()) {
    match t {
        "subscribe_presence" => { /* ... */ }
        "pi_envelope" => { /* ... */ }
        _ => warn!(peer = %peer_short, frame_type = %t, "unknown control frame type, dropping"),
    }
    continue;
}

match parse_line(&text) { /* OuterEnvelope path */ }
```

**Target State**:
```rust
pub enum DecodedRelayFrame {
    Outer(OuterEnvelope),
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
}

pub fn decode_relay_frame(text: &str) -> Result<DecodedRelayFrame, FrameDecodeError> {
    if has_type_discriminator(text)? {
        return match serde_json::from_str::<RelayInboundFrame>(text)? {
            RelayInboundFrame::Control(frame) => Ok(DecodedRelayFrame::Control(frame)),
            RelayInboundFrame::PiEnvelope(frame) => Ok(DecodedRelayFrame::PiEnvelope(frame)),
        };
    }

    Ok(DecodedRelayFrame::Outer(OuterEnvelope::parse_json(text)?))
}
```

**Implementation Notes**:
- Import generated relay-owned frame types; do not create temporary handwritten mirrors.
- Preserve compatibility: no top-level `type` means app↔Pi outer envelope, and generated/compat `OuterEnvelope` preserves current default-room behavior until canonical-session targeting changes it.
- Preserve `ct` size checks and content opacity.

**Acceptance Criteria**:
- [ ] `relay/src/protocol/frame.rs` is the single decode/classification boundary for inbound WebSocket text frames.
- [ ] The boundary consumes generated serde structs/enums for relay-owned frames.
- [ ] Unknown or malformed frame input fails before connection dispatch.
- [ ] Outer payload opacity and size checks are preserved.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Revert `relay/src/protocol/frame.rs` and return the routing loop to its current inline parse path. Generated protocol artifacts can remain because this story only consumes them.

---

### Step 2: Extract the authenticated connection actor shell
**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / lifecycle ownership  
**Files**: `relay/src/handlers/peer.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/mod.rs`  
**Story**: `epic-bold-relay-typed-actor-frame-dispatch-step-2`

**Current State**:
```rust
let registry = state.registry.clone();
let presence = state.presence.clone();
let rooms = state.rooms.clone();
let mesh = state.mesh.clone();
let mesh_auth = state.mesh_auth.clone();
let metrics = state.metrics.clone();

let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
let conn_id = registry.register(peer_id.clone(), room_meta, tx).await;
let mut last_presence_resp: Option<String> = None;
let mut last_rooms_resp: HashMap<String, String> = HashMap::new();
let mut control_check_limiter = ControlCheckLimiter::new();
```

**Target State**:
```rust
pub struct ConnectionActor {
    peer_id: String,
    peer_short: String,
    room_id: String,
    conn_id: u64,
    registry: Arc<PeerRegistry>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    mesh: Arc<MeshStore>,
    mesh_auth: Arc<MeshAuthCache>,
    metrics: Arc<FirehoseMetrics>,
    last_presence_resp: Option<String>,
    last_rooms_resp: HashMap<String, String>,
    control_check_limiter: ControlCheckLimiter,
}

pub enum ActorDispatch {
    Continue,
    Close,
    Send(String),
    SendMany(Vec<String>),
}
```

**Implementation Notes**:
- Keep `handle_peer` as the transport/lifecycle adapter: handshake, socket split, heartbeat, registry outbound `rx`, and final cleanup.
- Move per-connection dedup/rate-limit state with the actor.
- Do not split `PeerRegistry` or unify presence/rooms here.

**Acceptance Criteria**:
- [ ] Authenticated connection mutable state is in `ConnectionActor`.
- [ ] `handle_peer` reads text, decodes typed frame, calls actor dispatch, sends actor output, and performs heartbeat/cleanup.
- [ ] No observable wire behavior changes.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Inline actor state back into `handle_peer`; registration and cleanup remain in `handle_peer`, so rollback is mechanical.

---

### Step 3: Route app↔Pi outer envelopes through the typed actor
**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / boundary clarity  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, generated `OuterEnvelope` type, `relay/src/protocol/outer.rs`  
**Story**: `epic-bold-relay-typed-actor-frame-dispatch-step-3`

**Current State**:
```rust
let rewritten = OuterEnvelope {
    peer: peer_id.clone(),
    room: room_id.clone(),
    ct: env.ct,
};
let fwd_line = serde_json::to_string(&rewritten)
    .expect("OuterEnvelope serialisation is infallible");
if !registry.forward(&dest_peer, &dest_room, Message::Text(fwd_line), conn_id) {
    warn!(from = %peer_short, dest = %dest_tail, room = %dest_room, bytes = ct_len, "dest (peer, room) not found, dropping");
}
```

**Target State**:
```rust
impl ConnectionActor {
    async fn dispatch_outer(&mut self, env: OuterEnvelope) -> ActorDispatch {
        let ct_len = env.ct.len();
        let dest_peer = env.peer;
        let dest_room = env.room;
        let rewritten = OuterEnvelope {
            peer: self.peer_id.clone(),
            room: self.room_id.clone(),
            ct: env.ct,
        };
        if !self.registry.forward(&dest_peer, &dest_room, Message::Text(rewritten.to_json_string()), self.conn_id) {
            warn!(from = %self.peer_short, room = %dest_room, bytes = ct_len, "dest (peer, room) not found, dropping");
        }
        ActorDispatch::Continue
    }
}
```

**Implementation Notes**:
- Keep exact rewrite semantics: destination sees authenticated sender peer/room and original `ct` verbatim.
- Preserve skip-sender via `conn_id` and content-free logging.
- Wrap generated serialization if needed; do not duplicate a second `OuterEnvelope` struct.

**Acceptance Criteria**:
- [ ] No app↔Pi outer-envelope routing logic remains in the raw socket loop.
- [ ] `ct` remains opaque and byte-for-byte forwarded.
- [ ] Routing remains `(dest_peer, dest_room)` with sender rewrite to authenticated `(peer_id, room_id)`.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Move `dispatch_outer` back into the socket loop and call the previous `parse_line`/`registry.forward` path directly.

---

### Step 4: Route cross-PC `pi_envelope` through typed dispatch
**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contracts / relay opacity  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/pi_forward.rs`, generated `PiEnvelopeFrame`/agent-envelope types, `relay/src/peers/registry.rs`  
**Story**: `epic-bold-relay-typed-actor-frame-dispatch-step-4`

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
    /* authorization + forward_to_peer */
}
```

**Target State**:
```rust
pub async fn handle_pi_envelope(
    sender_peer_id: &str,
    frame: PiEnvelopeFrame,
    registry: &PeerRegistry,
    mesh: &MeshStore,
    cache: &MeshAuthCache,
) -> PiForwardResult {
    if !cache.is_authorized(sender_peer_id, frame.to_pc.as_str(), mesh) {
        return PiForwardResult::TransportError(make_transport_error(Some(&frame.envelope), "not_authorized"));
    }
    let outbound = PiEnvelopeInFrame { from_pc: sender_peer_id.to_owned(), envelope: frame.envelope };
    if registry.forward_to_peer(frame.to_pc.as_str(), Message::Text(outbound.to_json_string())) {
        PiForwardResult::Forwarded
    } else {
        PiForwardResult::TransportError(make_transport_error(Some(&outbound.envelope), "offline"))
    }
}
```

**Implementation Notes**:
- Preserve current cross-PC behavior, including peer-wide `forward_to_peer`; explicit `to_room` targeting belongs to `epic-bold-canonical-session-relay-opaque-targeting`.
- Preserve `_relay` transport-error envelopes with `not_authorized`, `offline`, and `bad_envelope` reasons correlated by `re`.
- Use authenticated `sender_peer_id` as ground truth, never human-readable `envelope.from`.

**Acceptance Criteria**:
- [ ] `handle_pi_envelope` accepts generated typed cross-PC frames, not raw `serde_json::Value`.
- [ ] The relay does not parse generic envelope bodies or endpoint-owned `session_id`.
- [ ] Transport-error shapes remain compatible with `PROTOCOL.md`.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Restore the `serde_json::Value` signature and raw field extraction. Peer-wide fanout remains unchanged, so rollback is isolated.

---

### Step 5: Replace the raw control-frame switch with exhaustive typed dispatch
**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / single source of truth / pattern drift  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, generated relay control frame types, `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/metrics.rs`  
**Story**: `epic-bold-relay-typed-actor-frame-dispatch-step-5`

**Current State**:
```rust
match t {
    "subscribe_presence" => { /* parse peers array + backfill */ }
    "unsubscribe_presence" => { /* parse peers array */ }
    "presence_check" => { /* parse peers array + rate-limit + dedup */ }
    "subscribe_rooms" => { /* parse peers array */ }
    "unsubscribe_rooms" => { /* parse peers array */ }
    "rooms_check" => { /* parse peers array + rate-limit + per-peer dedup */ }
    "room_meta_update" => { /* parse room_id/meta merge patch */ }
    "pi_envelope" => { /* cross-PC */ }
    _ => warn!(peer = %peer_short, frame_type = %t, "unknown control frame type, dropping"),
}
```

**Target State**:
```rust
impl ConnectionActor {
    async fn dispatch_control(&mut self, frame: RelayControlFrame) -> ActorDispatch {
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
- Preserve subscription replacement, presence backfill, check cost limiting, per-connection dedup, and `RoomMetaPatch` merge-patch behavior.
- Malformed control frames should fail at `decode_relay_frame`; valid typed `peers: []` remains valid where the schema permits it.
- Do not unify `PresenceManager` and `RoomManager` here; sibling `control-handlers` owns that decision.

**Acceptance Criteria**:
- [ ] `peer.rs` no longer branches on raw `frame.get("type")` or string constants for relay control dispatch.
- [ ] All current control frame behaviors are reachable through typed enum variants.
- [ ] Malformed control frame shapes fail at decode; valid empty peer lists retain documented behavior.
- [ ] Presence/rooms/meta tests continue to prove dedup, rate limiting, and merge-patch semantics.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Reintroduce the raw string match in `handle_peer` while keeping earlier actor/outer/cross-PC steps if useful. If control-plane behavior regresses broadly, revert this story alone.

## Implementation Order

1. `epic-bold-relay-typed-actor-frame-dispatch-step-1` (blocked on `epic-bold-generated-protocol-rust-codegen`)
2. `epic-bold-relay-typed-actor-frame-dispatch-step-2`
3. `epic-bold-relay-typed-actor-frame-dispatch-step-3`
4. `epic-bold-relay-typed-actor-frame-dispatch-step-4`
5. `epic-bold-relay-typed-actor-frame-dispatch-step-5`

## Atomic steps acknowledged

- Step 1 is strategically atomic with generated Rust protocol output. If generated frame names differ from the target snippets, adapt through `relay/src/protocol/frame.rs` rather than hand-writing a new protocol mirror.
- Step 5 is the only high-risk switch-over step because it removes the last raw control switch. It remains rollback-isolated from typed outer and cross-PC routing.
- Cross-PC room targeting is intentionally not folded into this refactor; that behavior-changing posture belongs to `epic-bold-canonical-session-relay-opaque-targeting`.


## Review — advanced to done (2026-06-30)

All 5 child steps `done` (typed decode boundary → connection actor shell →
outer-envelope routing → cross-PC pi_envelope → exhaustive typed dispatch).
The relay's inbound WebSocket frame handling is now fully typed-actor driven:
`decode_relay_frame` is the single classification boundary; `ConnectionActor`
owns per-connection dispatch state; the raw JSON control switch is gone.
Epic complete.
