---
id: epic-bold-relay-typed-actor-frame-dispatch-step-5
kind: story
stage: review
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-relay-typed-actor-frame-dispatch-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 5: Replace the raw control-frame switch with exhaustive typed dispatch

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / single source of truth / pattern drift  
**Files**: `relay/src/handlers/connection_actor.rs`, `relay/src/handlers/peer.rs`, generated relay control frame types, `relay/src/presence.rs`, `relay/src/rooms.rs`, `relay/src/metrics.rs`

## Current State

`handle_peer` matches every relay control frame by string and extracts fields with ad-hoc map lookups:

```rust
if let Some(t) = frame.get("type").and_then(|v| v.as_str()) {
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
    continue;
}
```

Bad `peers` shapes currently collapse to an empty peer list in some paths; the generated boundary should distinguish malformed frames from valid empty lists.

## Target State

The actor dispatches an exhaustive generated enum. Handler bodies may remain local in this story; the sibling `typed control handlers` feature will extract/unify the presence/rooms managers.

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

The socket loop has no `frame.get("type")` branch and no stringly typed control-frame routing.

## Implementation Notes

- Preserve the current high-level behavior: subscription replacement semantics, backfill after `subscribe_presence`, `presence_check`/`rooms_check` cost limit, per-connection dedup, and `RoomMetaPatch` merge-patch semantics.
- Malformed control frames should fail in `decode_relay_frame` before dispatch. A valid typed frame with `peers: []` remains valid where the schema permits it.
- Do not unify `PresenceManager` and `RoomManager` here; record any duplication discovered for the control-handlers sibling.
- Add tests that a newly generated control variant forces an exhaustive match compile error or a table-driven coverage assertion.

## Acceptance Criteria

- [x] `relay/src/handlers/peer.rs` no longer branches on raw `frame.get("type")` or string constants for relay control dispatch.
- [x] All current control frame behaviors are reachable through typed enum variants.
- [x] Malformed control frame shapes fail at decode; valid empty peer lists retain documented behavior.
- [x] Presence/rooms/meta update tests continue to prove dedup, rate limiting, and merge-patch semantics.
- [x] `cargo fmt --check`, `cargo clippy -- -D warnings`, and targeted relay tests pass from `relay/`.

## Risk

High. This is the final switch-over from the god-loop's raw JSON dispatch; mistakes can drop control-plane updates even when app↔Pi ciphertext routing still works.

## Rollback

Reintroduce the raw string match in `handle_peer` while keeping the actor shell from earlier steps if useful. If control-plane behavior regresses broadly, revert this story alone and leave typed outer/cross-PC routing intact.

## Implementation

- Exhaustive typed dispatch: `ConnectionActor::dispatch` routes `DecodedRelayFrame::Control` into the generated `RelayControlFrame` dispatch path; the exhaustive per-variant match and handler methods already live in `relay/src/handlers/control.rs` from the landed control-handlers slice, so this final switch-over did not touch that completed sibling-owned file.
- Raw-switch removal: verified `relay/src/handlers/peer.rs` has no `frame.get("type")` control switch and no stringly typed relay-control routing; the socket loop only decodes via `decode_relay_frame` and calls `actor.dispatch(frame)`.
- Malformed fail-fast: added connection-actor coverage proving malformed control `peers` shapes reject at `decode_relay_frame` before dispatch, while valid `peers: []` still decodes to the typed empty-list variant.
- Behavior preservation: existing presence/rooms/meta tests continue to cover subscription replacement, subscribe backfill, per-connection dedup, control-check rate limiting, and `RoomMetaPatch` merge-patch semantics. Added an actor-level `DecodedRelayFrame::Control` dispatch smoke test so the final typed actor route is exercised directly.
- Exhaustive coverage test: added a generated-control variant coverage assertion comparing constructed representative `RelayControlFrame` variants against `RELAY_CONTROL_FRAME_TYPES`; adding a generated variant without updating coverage now fails tests, and the production match remains Rust-exhaustive.
- Regen verdict: not applicable; no generated protocol files or generator were touched.
- Test counts: `cargo test` passed 148 relay tests total (93 lib, 3 integration, 13 mesh, 8 pi_forward, 10 presence, 2 protocol parity, 19 rooms; 0 doctests). Full verification also passed `cargo fmt --check`, `cargo clippy -- -D warnings`, and `cargo build` from `relay/`.
- Discrepancies from design: handler methods were already extracted into `handlers/control.rs` by the landed control-handlers work; this implementation respected the explicit collision guard not to edit that file and focused on final-route coverage and verification.
- Adjacent issues parked: none.
