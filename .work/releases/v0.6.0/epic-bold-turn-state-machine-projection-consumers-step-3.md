---
id: epic-bold-turn-state-machine-projection-consumers-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-turn-state-machine-projection-consumers
depends_on: [epic-bold-turn-state-machine-projection-consumers-step-2]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 3: Treat relay room metadata as a projection cache, not an authority

**Priority**: Medium
**Risk**: Medium
**Source Lens**: pattern drift / lifecycle convergence
**Files**: `relay/src/rooms.rs`, `relay/src/handlers/peer.rs`, `relay/src/peers/registry.rs`, `app/lib/protocol/protocol.dart`, `app/lib/data/transport/connection_manager.dart`, `relay/src/peers/registry.rs` tests

## Current State

```rust
pub struct RoomMeta {
    pub working: bool,
    pub started_at: i64,
}

pub struct RoomMetaPatch {
    pub working: Option<bool>,
}
```

```rust
let working_patch = meta_obj
    .and_then(|m| m.get("working"))
    .and_then(|v| v.as_bool());
let patch = RoomMetaPatch {
    model: model_patch,
    thinking: thinking_patch,
    session_id: session_id_patch,
    working: working_patch,
};
```

## Target State

```rust
/// Compatibility projection cached by the relay. The pi-extension is the only
/// authority for turn lifecycle; the relay stores and forwards the latest
/// projected boolean for room subscribers and rooms snapshots.
pub struct RoomMeta {
    pub working: bool,
    pub started_at: i64,
}

/// None = absent from patch, Some(false) = terminal/idle projection.
pub struct RoomMetaPatch {
    pub working: Option<bool>,
}
```

```dart
RoomTurnProjection roomTurnProjection(String epk, String roomId) {
  if (_status is! StatusOnline || !isRoomLive(epk, roomId)) {
    return const RoomTurnProjection(status: AppTurnStatus.stale);
  }
  final room = _roomById(epk, roomId);
  return room?.working == true
      ? const RoomTurnProjection(status: AppTurnStatus.working)
      : const RoomTurnProjection(status: AppTurnStatus.idle);
}
```

## Implementation Notes

- Keep relay parsing shape unchanged: `working` is a non-null bool and `false` is the terminal projection.
- Update comments/tests so future agents do not treat relay state as a second turn state machine. The relay should not derive turn phase, reply target, or cancel target.
- `rooms` snapshots are authoritative for currently live rooms; app-side cached rooms missing from the snapshot or ended by `room_ended` must not remain visually working.
- Add relay registry tests for true→false patches, absent `working` preserving current state, `rooms_of` returning the latest projected value, and disconnect/room end causing app projection `working:false` through the live-room gate.
- If Step 2 already moves app interpretation to `RoomTurnProjection`, this step should tighten relay tests and comments rather than churn app code again.

## Acceptance Criteria

- [x] `cargo test` targeted relay registry/room tests pass from `relay/`.
- [x] Relay tests show `room_meta_updated` broadcasts post-patch `working:false` and that absent `working` does not zero an active projection.
- [x] App room-projection tests show ended/offline/stale rooms render not-working even if their cached `RoomInfo.working` was last true.
- [x] No relay code attempts to inspect or synthesize `turnId`, `replyTo`, or phase; it only forwards the projected compatibility bool.
- [x] `app/lib/protocol/protocol.dart` keeps field names compatible with existing `working` wire frames.

## Implementation

- Files changed: `relay/src/rooms.rs`, `relay/src/peers/registry.rs`, `app/test/transport/connection_manager_working_test.dart`.
- Relay room metadata is documented as a compatibility projection cache: `working` is forwarded from the pi-extension as the latest projected bool, `None`/absent patches preserve the current projection, and `Some(false)` is the terminal idle projection. No relay path derives turn phase, reply target, cancel target, `turnId`, or `replyTo`.
- Relay registry tests added: `rooms_of_returns_latest_working_projection` proves `rooms_of` returns the latest projected `working` after true→false patches; `unregister_last_conn_ends_room_and_removes_it_from_rooms_of` proves last disconnect emits `room_ended` and removes the room from authoritative live snapshots. Existing registry tests preserve `room_meta_updated` `working:false` broadcasts and absent-`working` preservation.
- App convergence tests added in `test/transport/connection_manager_working_test.dart`: `room_ended` clears cached `working:true` and projects stale/not-working; a fresh `RoomsSnapshot` missing a previously-working room clears its cached working bit and projects stale/not-working; offline projection assertion now checks `RoomTurnProjection.stale` as well as `isRoomWorking == false`.
- `app/lib/data/transport/connection_manager.dart` already had the Step-2 `RoomTurnProjection` live-room gate and snapshot-missing working clear, so this step tightened tests/comments rather than churning the source. `app/lib/protocol/protocol.dart` and relay `peer.rs` wire parsing were left shape-compatible: the `working` field name and bool semantics remain unchanged.
- Verification: `cd relay && cargo test peers::registry -- --nocapture` passed (13 registry tests); `cd relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed (70 unit + integration/mesh/pi_forward/presence/rooms suites); `cd app && flutter test test/transport/connection_manager_working_test.dart` passed (7 tests); `cd app && flutter test test/transport/` passed (64 tests). `flutter pub get` passed. `flutter analyze` was run and reported only the known unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802`, exiting non-zero per current Flutter analyzer behavior.
- Discrepancies from design: none. Step 2 had already landed the app source-level `RoomTurnProjection`; this story adds focused app tests without editing the collision-guarded `app/test/transport/connection_manager_test.dart`.
- Adjacent issues parked: none.

## Rollback

Revert relay/app interpretation changes to the prior bool cache. Do not remove tests that prove cached ended rooms must not show `working:true`; bounce the story if rollback is needed because that is the absorbed bug class.

## Review

Approved (2026-06-30) with deeper verification — cross-cutting HIGH-risk story.
Independently re-ran: relay `cargo fmt --check` clean, `cargo clippy -- -D
warnings` clean, `cargo test` 124 passed / 0 failed (70 lib + 3 integ + 13 mesh +
9 pi_forward + 10 presence + 19 rooms; +2 new registry snapshot tests); app
`flutter test test/transport/` 64 passed / 0 failed. Commit `a6608a4` scoped to
relay rooms.rs/registry.rs + new app test file + story .md; no collision-guard
violations (did not touch connection_manager_test.dart / reachability_adapter /
sync_service / control.rs).

Core convergence invariant verified directly in code + tests: `room_ended`
clears cached `working:true` and projects `stale`/not-working (app test); a fresh
`RoomsSnapshot` missing a previously-working room clears its working bit and
projects stale (app test); relay `rooms_of` is the authoritative live-room
snapshot carrying the latest projected `working` (relay test
`rooms_of_returns_latest_working_projection`), and last-disconnect emits
`room_ended` + removes from snapshot (relay test). The agent's "deviation" (not
re-touching connection_manager.dart/protocol.dart/peer.rs source) is legitimate
and documented — Step 2 already landed the app `RoomTurnProjection` gate; this
step correctly focused on relay snapshot authority + app convergence coverage.
