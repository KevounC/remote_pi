---
id: epic-bold-canonical-session-app-attribution-hydration-step-2
kind: story
stage: done
tags: [refactor]
parent: epic-bold-canonical-session-app-attribution-hydration
depends_on: [epic-bold-canonical-session-app-attribution-hydration-step-1]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 2: Retire the transport legacy no-room fail-open route

## Current State
```dart
if (frame.containsKey('peer') && frame.containsKey('ct')) {
  final bytes = _b64Decode(frame['ct'] as String);
  final senderRoom = frame['room'] as String?;
  if (senderRoom != null && senderRoom != transport._activeRoom) {
    debugPrint('[ws-in] ... DROPPED (room-mismatch)');
    return;
  }
  // Legacy Pis without `room` route unconditionally.
  transport._queue.add(bytes);
  return;
}
```

A relay/app envelope with no `room` bypasses room demux and reaches `SyncService`. Before session gating existed this was a direct contamination path; after Step 1 it is still dead-weight compatibility that undermines the correctness boundary.

## Target State
```dart
if (frame.containsKey('peer') && frame.containsKey('ct')) {
  final bytes = _b64Decode(frame['ct'] as String);
  final senderRoom = frame['room'] as String?;
  if (senderRoom == null || senderRoom.isEmpty) {
    debugPrint('[ws-in] kind=envelope DROPPED (missing-room)');
    return;
  }
  if (senderRoom != transport._activeRoom) {
    debugPrint('[ws-in] kind=envelope sender_room=$senderRoom DROPPED (room-mismatch)');
    return;
  }
  transport._queue.add(bytes);
  return;
}
```

## Implementation Notes
- Remove the legacy no-room unconditional route in `app/lib/data/transport/ws_transport.dart`.
- Keep control frames (`peer_online`, `rooms`, `room_announced`, `room_meta_updated`) on the control stream; this step only tightens chat-bearing relay envelopes with `{peer, room, ct}`.
- Extract the post-auth envelope demux into a tiny testable helper if direct `IOWebSocketChannel` tests are awkward. The helper should return `enqueue`, `dropMissingRoom`, `dropRoomMismatch`, `control`, or `dropMalformed` so tests do not need a live socket.
- Preserve base64 decoding behavior and malformed-frame drops; do not add relay parsing of `session_id`.
- This step pairs with Step 1: transport enforces room attribution, `SyncService` enforces canonical session attribution.

## Acceptance Criteria
- [ ] Envelope frames missing `room` are dropped and never reach `PeerChannel.serverMessages` / `SyncService`.
- [ ] Envelope frames for a non-active room are still dropped.
- [ ] Envelope frames for the active room are delivered unchanged.
- [ ] Control frames still emit through `controlFrames`.
- [ ] Targeted transport/unit tests pass; if no existing seam exists, the new helper has deterministic tests.

## Risk
Medium. Legacy Pi-extension builds that omit `room` will no longer stream chat into the app. This is intentional for the fork-private clean-room path because accepting no-room chat frames preserves the contamination vector.

## Rollback
Restore the `senderRoom == null` unconditional enqueue branch. Do not replace it with `session_id` parsing in transport; session validation belongs in `SyncService`.

## Implementation notes
- Extracted `demuxPostAuthInboundFrame` from `WsTransport.connect` into `app/lib/data/transport/ws_transport.dart` as a pure helper.
- Added new pure demux outcome enum/class: `WsInboundFrameKind` / `WsInboundFrameDecision`.
- Enforced drop behavior for missing or empty room and room mismatch before any queueing.
- Kept control-frame parsing on the same boundary: `{peer, ct}` envelopes are still routed through queueing logic and control frames still emit through `controlFrames`.
- Added unit tests in `app/test/data/transport/ws_transport_demux_test.dart` covering all five outcomes: `enqueue`, `dropMissingRoom`, `dropRoomMismatch`, `control`, `dropMalformed`.

## Review (2026-06-30, fast-lane)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 8efd13e` — only `app/lib/data/transport/ws_transport.dart` + `app/test/data/transport/ws_transport_demux_test.dart` + this story file changed; no collision with other app agents (connection_manager.dart / protocol.g.dart untouched).
- Confirmed legacy no-room bypass comment/route removed; `demuxPostAuthInboundFrame` pure helper + `WsInboundFrameKind`/`WsInboundFrameDecision` types present; all 5 outcomes (`enqueue`, `dropMissingRoom`, `dropRoomMismatch`, `control`, `dropMalformed`) reachable.
- `cd app && flutter test test/data/transport/ws_transport_demux_test.dart` (PUB_CACHE set) — 5/5 pass.
- `cd app && flutter analyze` — only the known-unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802` (documented; not a failure).
- Acceptance criteria satisfied: missing-room drop, room-mismatch drop, active-room enqueue, control-frame routing, deterministic helper tests.
