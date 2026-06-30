---
id: epic-bold-turn-state-machine-projection-consumers-step-2
kind: story
stage: review
tags: [refactor]
parent: epic-bold-turn-state-machine-projection-consumers
depends_on: [epic-bold-turn-state-machine-projection-consumers-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 2: Replace mobile chat working booleans with an app turn projection

**Priority**: High
**Risk**: High
**Source Lens**: missing abstraction / lifecycle convergence
**Files**: `app/lib/domain/session_state.dart`, `app/lib/domain/transcript/transcript_projection.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/data/transport/connection_manager.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `app/test/data/sync/sync_service_test.dart`, `app/test/data/transport/connection_manager_test.dart`

## Current State

```dart
bool get isWorking {
  final epk = _activePeer?.remoteEpk;
  final roomWorking = epk != null && _conn.isRoomWorking(epk, _activeRoomId);
  return roomWorking || _working || _streaming != null;
}

String? get cancelTargetId => _streaming?.inReplyTo ?? _sync.workingReplyTo;
```

```dart
bool _working = false;
String? _workingReplyTo;

void _setWorking(bool on, {String? preview, String? replyTo}) {
  _setActivity(on ? SessionActivity.working : SessionActivity.idle, preview: preview);
  final epk = _activeEpk;
  if (epk != null) {
    _conn.markRoomWorking(epk, _activeRoomId, on);
  }
  if (on) {
    if (replyTo != null) _workingReplyTo = replyTo;
  } else {
    _workingReplyTo = null;
  }
  if (_working == on) return;
  _working = on;
  if (!_workingController.isClosed) _workingController.add(on);
}
```

## Target State

```dart
enum AppTurnStatus { idle, working, awaitingTool, streaming, done, error, stale }

final class AppTurnProjection {
  const AppTurnProjection({
    required this.status,
    this.turnId,
    this.replyTo,
    this.error,
  });

  final AppTurnStatus status;
  final String? turnId;
  final String? replyTo;
  final String? error;

  bool get working => switch (status) {
    AppTurnStatus.working || AppTurnStatus.awaitingTool || AppTurnStatus.streaming => true,
    AppTurnStatus.idle || AppTurnStatus.done || AppTurnStatus.error || AppTurnStatus.stale => false,
  };

  String? get cancelTargetId => working ? replyTo : null;
}

AppTurnProjection deriveChatTurnProjection({
  required RoomTurnProjection room,
  required TranscriptTurnView transcript,
  required StreamingMessage? streaming,
}) { /* room authoritative when fresh; transcript is active-room compat/local optimism */ }
```

```dart
bool get isWorking => _turnProjection.working;
String? get cancelTargetId => _turnProjection.cancelTargetId;
```

## Implementation Notes

- Extend the existing transcript sibling seam instead of inventing unrelated names: keep `status`, `turnId`, and `replyTo` aligned with `TranscriptTurnView`.
- `ConnectionManager` should expose a room-level projection (`idle`/`working`/`stale`) rather than a sticky bool. A room not in `_liveRoomIds`, a non-online connection, or a reconnect snapshot not yet hydrated projects `stale`/`idle` with `working:false`.
- `SyncService` may still produce active-room local optimism from `UserMessageSubmitted`, `AgentChunk`, `AgentDone`, `Cancelled`, `Error`, and send-timeout events, but it should publish an `AppTurnProjection`/`TranscriptTurnView` stream rather than `_working` and `_workingReplyTo` as independent mutable fields.
- Remove or narrow `ConnectionManager.markRoomWorking`; if kept temporarily for compatibility, it must update only the active-room projection and must clear on `AgentDone`, error/cancel, non-online status, session switch, and dispose.
- Preserve UI behavior: the chat pill and composer still show working promptly after send and still expose stop/cancel while an active turn exists.

## Acceptance Criteria

- [x] `flutter test test/data/sync/sync_service_test.dart` passes from `app/`.
- [x] Targeted `ConnectionManager` tests prove `isRoomWorking`/room projection is false when the room is ended, absent from a fresh `RoomsSnapshot`, connection is non-online, or reconnect hydration reports `working:false`.
- [x] `ChatViewModel.isWorking` and `cancelTargetId` derive from one projection object; they no longer OR `roomWorking || _working || _streaming != null`.
- [x] `SyncService` convergence tests cover agent done, provider error, cancel/abort, send timeout, compaction/history replay, session switch, connection loss/reconnect, and dispose.
- [x] The app domain projection imports no Flutter widgets, storage boxes, WebSocket channel, or `BuildContext`.

## Rollback

Restore the existing `_working` / `_workingReplyTo` stream and `ChatViewModel` OR logic. Keep any pure projection tests if they expose a real convergence bug, but do not weaken them to hide sticky `working:true`.

## Implementation notes

- Files changed: `app/lib/domain/session_state.dart`, `app/lib/domain/transcript/transcript_projection.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/data/transport/connection_manager.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `app/test/data/sync/sync_service_test.dart`, `app/test/data/transport/connection_manager_test.dart`.
- Projection shape: added pure-domain `AppTurnStatus`, `AppTurnProjection`, and `RoomTurnProjection`; `TranscriptTurnView` now carries `status`/`turnId`/`replyTo` aligned to the canonical app turn status, with `TranscriptTurnStatus` kept only as compatibility aliases to avoid a second enum.
- SyncService: replaced independent `_working` / `_workingReplyTo` mutable fields with a single `TranscriptTurnView`/`AppTurnProjection` source; legacy `isWorking`, `workingStream`, and `workingReplyTo` now derive from that projection.
- ConnectionManager: added `roomTurnProjection`; `isRoomWorking` derives from it and returns false for ended, absent, non-online, and stale/unhydrated rooms. `markRoomWorking` is narrowed to the active live room and terminal/lifecycle paths clear cached active-room working state.
- ChatViewModel: `isWorking` and `cancelTargetId` now read one `_turnProjection` object derived by `deriveChatTurnProjection(room, transcript, streaming)`; the old OR logic is gone.
- Convergence tests added: agent done, provider error, cancel/abort, send timeout, compaction live event, history replay, session switch, connection loss/reconnect, and dispose all assert `working:false`/no cancel target; connection-manager tests cover room ended, room absent from fresh snapshot, non-online connection, and reconnect hydration with `working:false`.
- Verification: `HOME=/tmp/pi-dart-home PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter pub get` passed; `flutter test test/data/sync/sync_service_test.dart test/data/transport/connection_manager_test.dart` passed; `flutter test test/data/transport/connection_manager_test.dart` passed separately; `flutter analyze` reports only the known unrelated `axisAlignment` deprecation in `lib/ui/chat/widgets/input_bar.dart:802` and exits non-zero because Flutter treats the info as an issue in this environment.
- Discrepancies from design: `TranscriptTurnStatus` remains as an alias-only compatibility wrapper over `AppTurnStatus` so older transcript tests/callers continue to compile without creating an independent variant source.
- Adjacent issues parked: none.
