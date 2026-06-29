---
id: epic-bold-relay-typed-actor-frame-dispatch-step-2
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-relay-typed-actor-frame-dispatch-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Extract the authenticated connection actor shell

**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / lifecycle ownership  
**Files**: `relay/src/handlers/peer.rs`, `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/mod.rs`

## Current State

After auth, `handle_peer` owns every connection concern inline: registry registration, presence/rooms handles, mesh handles, dedup caches, rate limiter, sink writes, inbound parsing, outbound registry messages, heartbeat, and cleanup.

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

This makes the actor state implicit and keeps future handler extraction coupled to the WebSocket loop.

## Target State

Move authenticated connection state into an explicit actor object. The axum handler stays the transport adapter; the actor owns typed dispatch state and returns outbound text frames for the adapter to send.

```rust
// relay/src/handlers/connection_actor.rs
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

impl ConnectionActor {
    pub async fn dispatch(&mut self, frame: DecodedRelayFrame) -> ActorDispatch {
        match frame {
            DecodedRelayFrame::Outer(frame) => self.dispatch_outer(frame).await,
            DecodedRelayFrame::Control(frame) => self.dispatch_control(frame).await,
            DecodedRelayFrame::PiEnvelope(frame) => self.dispatch_pi_envelope(frame).await,
        }
    }
}
```

`handle_peer` keeps handshake, socket split, heartbeat ping, `rx.recv()`, and final unregister/unsubscribe cleanup.

## Implementation Notes

- Move `ControlCheckLimiter`, `control_check_cost`, and dedup caches with the actor; they are per-connection state, not protocol globals.
- Keep lifecycle cleanup in `handle_peer` for this step: register before loop, unregister/rooms cleanup after loop.
- Do not split `PeerRegistry` or unify presence/rooms in this story; those are sibling features.
- Unit-test actor construction and rate-limit/dedup state in isolation where possible; integration behavior remains covered by existing registry/control tests.

## Acceptance Criteria

- [ ] Authenticated connection mutable state is in `ConnectionActor`, not scattered through `handle_peer` locals.
- [ ] `handle_peer` is a transport/lifecycle loop: handshake, read text, call `decode_relay_frame`, call actor dispatch, send actor output, heartbeat, cleanup.
- [ ] No observable wire behavior changes for existing frames.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and targeted relay tests pass from `relay/`.

## Risk

Medium. The highest risk is moving cleanup or sink-break behavior incorrectly; a failed send must still close the loop and unregister exactly once.

## Rollback

Inline the actor state back into `handle_peer` and remove `connection_actor.rs`. Because registration/cleanup remains in `handle_peer`, rollback is mechanical.
