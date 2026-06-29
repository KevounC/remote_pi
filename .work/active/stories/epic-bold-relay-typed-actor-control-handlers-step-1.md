---
id: epic-bold-relay-typed-actor-control-handlers-step-1
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-control-handlers
depends_on: [epic-bold-relay-typed-actor-frame-dispatch]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Add the typed control-handler dispatch shell

**Priority**: High  
**Risk**: Medium  
**Source Lens**: code smell / generated contracts / fail-fast boundary  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/control.rs`, `relay/src/handlers/peer.rs`, generated relay control frame types, `relay/src/metrics.rs`

## Current State

The authenticated routing loop owns the entire relay control plane through a raw JSON string switch:

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

`parse_bounded_control_peers` treats a non-array `peers` field as an empty list and silently drops non-string entries, so malformed frames can clear subscriptions.

## Target State

Introduce the control-handler module that the frame-dispatch actor calls with generated control frames:

```rust
impl ConnectionActor {
    pub async fn dispatch_control(&mut self, frame: RelayControlFrame) -> ActorDispatch {
        ControlHandlers::new(self).handle(frame).await
    }
}

pub struct ControlHandlers<'a> {
    actor: &'a mut ConnectionActor,
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

Peer-list shape validation happens before handler behavior:

```rust
fn bounded_peer_list(frame_type: &'static str, peers: Vec<String>) -> Result<Vec<String>, ControlFrameError> {
    if peers.len() > MAX_CONTROL_FRAME_PEERS {
        return Err(ControlFrameError::TooManyPeers { frame_type, requested: peers.len() });
    }
    Ok(peers)
}
```

Generated deserialization rejects non-array and non-string peer entries; missing `peers` may still default to `[]` only where the canonical schema says that is valid.

## Implementation Notes

- This story depends on `epic-bold-relay-typed-actor-frame-dispatch` because it consumes the actor and generated `RelayControlFrame` variants it introduces.
- Keep rate limiting, dedup caches, metrics counters, and registry calls in later stories; this story only establishes the handler shape and shared validation/error vocabulary.
- Fail malformed peer-list frames closed by relying on generated deserialization plus the explicit length cap. Do not reintroduce `filter_map` or non-array-as-empty behavior.
- Unknown typed variants should be impossible once the generated enum parses; unknown wire types remain a decode-layer warn/drop.

## Acceptance Criteria

- [ ] `ConnectionActor::dispatch_control` delegates to `relay/src/handlers/control.rs` instead of a raw switch in `peer.rs`.
- [ ] Control handlers receive generated typed frames, not `serde_json::Value`.
- [ ] Non-array or mixed-type `peers` frames fail before subscription mutation.
- [ ] Peer-list size limits remain enforced.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Medium. This changes the malformed-frame boundary; happy-path subscribe/check/unsubscribe behavior should be preserved, but clients sending invalid `peers` values will now be dropped rather than interpreted as an empty list.

## Rollback

Revert `relay/src/handlers/control.rs` and call the prior raw switch from `handle_peer`/`ConnectionActor`. If rollback is needed after later stories, keep generated frame decode but route control variants through the old branch logic temporarily.

## Implementation notes
- Files changed: `relay/src/handlers/control.rs`, `relay/src/handlers/mod.rs`, `relay/src/handlers/peer.rs`.
- Tests added: unit tests in `relay/src/handlers/control.rs` prove missing peers default to empty, non-array peers fail closed, mixed-type peers fail closed, and peer-list size limits remain enforced.
- Discrepancies from design: `epic-bold-relay-typed-actor-frame-dispatch` has not landed a `ConnectionActor`, `ActorDispatch`, or generated `RelayControlFrame` in this checkout, so the actor delegation half could not be wired without inventing a parallel handwritten enum. Implemented the safe step-1 subset against the designed shape: a typed control validation module plus fail-closed peer-list boundary consumed by the current `peer.rs` switch. This avoids blocking the future actor/generated migration and removes the dangerous non-array-as-empty/filter-map behavior now.
- Adjacent issues parked: none.
- Verification: `cargo fmt`, `cargo fmt --check`, and `cargo test handlers::control` passed from `relay/`. Full relay `cargo clippy -- -D warnings` and `cargo test` were not run in this slice after the dependency-blocked partial; they remain required when the actor dispatch shell lands.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review with dependency-aware scope. Implementation commit `37136da` inspected. The actor/generated-frame delegation remains explicitly deferred because `ConnectionActor` / generated `RelayControlFrame` are not present yet; the implemented subset is sound for this step: `handlers/control.rs` centralizes peer-list validation, `peer.rs` uses it for subscribe/check paths, malformed non-array/mixed peer lists no longer become subscription-clearing subscribe frames, and peer-list limits remain enforced. Verification run from `relay/`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed.
