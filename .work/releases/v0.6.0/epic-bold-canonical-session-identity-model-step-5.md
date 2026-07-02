---
id: epic-bold-canonical-session-identity-model-step-5
kind: story
stage: done
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: [epic-bold-canonical-session-identity-model-step-4]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 5: Re-key endpoint projections by canonical session

## Current State
```dart
// app/lib/data/local/boxes.dart
static String msgsBoxName(String epk, String roomId) =>
    'msgs_${toAppEpk(epk)}__$roomId';
static String sessionKey(String epk, String roomId) => '$epk:$roomId';
```

```dart
// cockpit/lib/app/cockpit/domain/entities/session_info.dart
final String path; // absolute JSONL path used as switch_session target
final String id;   // short suffix of the session file
```

App persistence and UI selection are keyed by peer+room; Cockpit has a local JSONL session id/path that is not named as the same domain concept as the remote `session_id`.

## Target State
```dart
// app/lib/domain/entities/remote_session.dart
class RemoteSessionRef {
  final String peerId;
  final String roomId;
  final String sessionId;
  String get storageKey => '$peerId:$roomId:$sessionId';
}

// app/lib/data/local/boxes.dart
static String msgsBoxName(String epk, String roomId, String sessionId) =>
    'msgs_${toAppEpk(epk)}__${sanitize(roomId)}__${sanitize(sessionId)}';
static String sessionKey(String epk, String roomId, String sessionId) =>
    '$epk:$roomId:$sessionId';
```

Cockpit keeps using Pi's JSONL path for local `switch_session`, but names the projected value as `piSessionId`/`sessionId` and treats it as the local equivalent of `RemoteSession.sessionId`; it does not introduce relay or pairing into Cockpit.

## Implementation Notes
- App migration can be clean-room: abandon old peer+room message boxes the same way v1 `session_history` was abandoned, then re-sync from Pi for the active `session_id`.
- `SessionSelection`, `ChatViewModel`, read repositories, runtime records, and session index keys must pass the full `RemoteSessionRef` instead of loose `(epk, roomId)` pairs where the value identifies persisted transcript state.
- Keep room-level liveness/working snapshots keyed by `(epk, roomId)` in `ConnectionManager`; that is relay reachability, not transcript identity. The session id gates transcript mutation.
- Cockpit remains local-only. This story only aligns naming/projection so a future patchbay/session core can map local and remote sessions without a conceptual fork.

## Acceptance Criteria
- [ ] App transcript boxes and durable session index are keyed by `(peer, room, session_id)`.
- [ ] Room reachability remains keyed by `(peer, room)`; transcript mutation is keyed/gated by `session_id`.
- [ ] Existing old `(peer, room)` boxes are ignored or migrated by a documented one-time clean-room re-sync path.
- [ ] Cockpit terminology distinguishes local Pi JSONL path from canonical session id without adding remote transport behavior.
- [ ] Tests cover two different `session_id`s on the same `(peer, room)` not sharing messages.
- [ ] `flutter test` targeted app persistence tests and `flutter analyze` pass or blockers are reported.

## Risk
High. Re-keying persistence can appear as lost history until re-sync completes. The rollback path must preserve old boxes until the new key is verified.

## Rollback
Keep old boxes untouched; restore app reads/writes to `(epk, roomId)` keys and remove the Cockpit naming alignment. Because old boxes are not deleted, rollback recovers previous local cache behavior.

## Implementation
- Re-key approach: app transcript `msgs_*` boxes and the durable `sessions_index` key now use the canonical `RemoteSessionRef` shape `(peer, room, session_id)` via `RemoteSessionRef.storageKey`; message and transcript event box filenames sanitize peer/room/session path segments. `RemoteSessionRef` keeps the existing app-facing `peerEpk` field and adds `peerId` as the canonical alias so the model aligns with sync_service's existing `_activeRef` instead of forking it.
- Session selection/UI: tablet `SessionSelection` now carries a full `RemoteSessionRef`, the detail-pane key includes `sessionId`, and sheet-dismiss/highlight tests cover same-room session rotations. Room reachability and Home working/live dots still query `ConnectionManager` by `(peer, room)` only.
- Clean-room migration/re-sync path: old peer+room-only message boxes are deliberately never opened or deleted. A freshly keyed canonical box starts empty, then `SyncService.requestSync()`/Pi `session_history` replay repopulates it for the active `session_id`. Rollback can restore old `(peer, room)` reads because the old cache files remain untouched.
- Tests added/updated: `read_repository_test` now proves two different `session_id`s on the same `(peer, room)` read from different boxes; the existing `sync_service_test` same-room session-rotation test still proves writer/index isolation and old-box preservation; action tests now seed canonical `session_id` before action dispatch.
- Verification: `flutter test` full app suite passes. `flutter analyze` reports only the known unrelated `axisAlignment` deprecation at `app/lib/ui/chat/widgets/input_bar.dart:802`.
- Deviations: cockpit terminology alignment was not changed because the caller explicitly scoped this wave to app-only work and forbade cockpit edits due concurrent ownership. `SyncService`/transcript reducer files were not rewritten; this work only aligns call sites and persistence keys with their existing `RemoteSessionRef` concept.

## Review

Approved (2026-06-30) with deeper verification — HIGH-risk persistence re-key.
Independently re-ran: full app `flutter test` → 596/596; `flutter analyze` clean
in owned files (only known `axisAlignment` info). Commit `fcb4baf` scoped to the
re-key layer (boxes.dart, remote_session_ref.dart, SessionSelection/routing,
UI consumers, tests); collision guard held — did NOT rewrite sync_service
reducer / connection_manager / reachability_adapter (aligned with existing
_activeRef instead of forking).

Load-bearing invariants verified directly in code + tests:
- **Re-key**: `msgsBoxName` = `msgs_<epk>__<roomId>__<sessionId>`; `sessionKey`
  = `RemoteSessionRef.storageKey` = `peerId:roomId:sessionId`. Transcript-event
  boxes similarly keyed.
- **Two-session-id isolation** (acceptance criterion): `read_repository_test`
  puts `from session a` / `from session b` in same-(peer,room) different-
  sessionId boxes; `watchMessages(first)` returns ONLY `from session a`,
  `watchMessages(second)` ONLY `from session b`. Real isolation, not a mock.
- **Rollback safety**: old peer+room boxes deliberately never opened/deleted;
  clean-room re-sync repopulates the new canonical box; old cache files intact.
- **Reachability boundary preserved**: room liveness/working stays keyed by
  `(peer, room)` via ConnectionManager; `session_id` gates transcript mutation
  only (per the story's explicit split).
Cockpit terminology alignment deferred (scoped app-only this wave) — legitimate.
