---
id: epic-bold-canonical-session-app-attribution-hydration-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-canonical-session-app-attribution-hydration
depends_on: [epic-bold-canonical-session-app-attribution-hydration-step-2]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 3: Key app persistence by canonical session id

## Current State
```dart
// app/lib/data/local/boxes.dart
static String msgsBoxName(String epk, String roomId) =>
    'msgs_${toAppEpk(epk)}__$roomId';

static String sessionKey(String epk, String roomId) => '$epk:$roomId';
```

```dart
// app/lib/data/local/records/session_index_record.dart
class SessionIndexRecord {
  final String epk;
  final String roomId;
  final DateTime? sessionStartedAt;

  String get key => '$epk:$roomId';
}
```

The durable app store still treats `(peer, room)` as the transcript/session key. Two canonical sessions on the same room can share a Hive message box and session-index row.

## Target State
```dart
final class RemoteSessionRef {
  const RemoteSessionRef({
    required this.peerEpk,
    required this.roomId,
    required this.sessionId,
  });

  final String peerEpk;
  final String roomId;
  final String sessionId;

  String get storageKey => '$peerEpk:$roomId:$sessionId';
}

static String msgsBoxName(RemoteSessionRef ref) =>
    'msgs_${toAppEpk(ref.peerEpk)}__${ref.roomId}__${_safe(ref.sessionId)}';

class SessionIndexRecord {
  final String epk;
  final String roomId;
  final String sessionId;

  String get key => '$epk:$roomId:$sessionId';
}
```

## Implementation Notes
- Introduce one app-side `RemoteSessionRef`/`ActiveSessionRef` value and pass it through `SyncService`, `LocalBoxes`, read repositories, runtime writes, and session-index writes. Do not keep independent string-building call sites.
- Keep `ConnectionManager` reachability keyed by `(epk, roomId)`. Room liveness/working snapshots are transport reachability, not transcript identity.
- Do not destructively migrate or delete old `msgs_<epk>__<room>` boxes. Treat them as legacy cache that the new session-scoped path ignores; the Pi can hydrate the canonical box through `session_sync`.
- If the active session id rotates for the same `(epk, roomId)`, reset in-memory stream/working/pending state and load the new session-scoped box. Stale delayed frames are still rejected by Step 1.
- Update `SessionIndexRecord.fromJson` defensively: records without `session_id` are legacy and should not masquerade as the current canonical session.

## Acceptance Criteria
- [ ] Two different `session_id`s for the same `(epk, roomId)` use different message boxes and session-index keys.
- [ ] A session id rotation on the same room does not show the prior session's messages in the new active chat.
- [ ] Runtime/connection records used by UI do not report stale live/working state while disconnected.
- [ ] Old `(epk, room)` boxes are not deleted during the change.
- [ ] Read repositories and chat ViewModel tests are updated to pass `RemoteSessionRef` or otherwise resolve the active canonical session through one shared helper.

## Risk
High. This touches persistence and read-side lookup paths. The mitigation is to make old data ignored/re-hydrated rather than migrated in place, and to keep reachability keyed separately by `(peer, room)`.

## Rollback
Restore `LocalBoxes` and `SessionIndexRecord` keys to `(epk, roomId)`. The new session-scoped boxes can remain on disk; rollback should not delete either old or new boxes.

## Implementation notes
- Files changed: `app/lib/domain/entities/remote_session_ref.dart`, `app/lib/data/local/boxes.dart`, `app/lib/data/local/records/session_index_record.dart`, `app/lib/data/repositories/home_read_repository.dart`, `app/lib/data/repositories/session_read_repository.dart`, `app/lib/data/sync/session_gate.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, and targeted local/read/sync/chat tests.
- Implemented one canonical app-side `RemoteSessionRef { peerEpk, roomId, sessionId }` with `storageKey`, routed session-scoped message boxes and session-index rows through it, and kept volatile runtime keys room-scoped through `LocalBoxes.runtimeKey(epk, roomId)`.
- `SessionIndexRecord` now requires `sessionId`, writes `session_id`, derives `key` from `RemoteSessionRef.storageKey`, and treats records without `session_id` as legacy via `tryFromJson`/`fromJson` fail-fast behavior so old rows cannot masquerade as canonical sessions.
- `SyncService` now binds to a full active `RemoteSessionRef`, opens/reloads session-scoped boxes on session-id rotation, resets streaming/working/queued/pending timers and transcript projection buffers on canonical session switch, and leaves old peer+room message boxes untouched.
- `ChatViewModel` now refreshes its read subscription from `SyncService.activeSessionRef` and swaps to the new session-scoped message stream when room metadata reports a rotated session id, so the new active chat starts from the new canonical box rather than the prior room cache.
- Tests added/updated: session-index legacy rejection and key roundtrip, read repository `RemoteSessionRef` watch path, SyncService same-room two-session box/index separation plus legacy-box non-deletion and disconnected runtime assertions, and ChatViewModel same-room session rotation not showing prior messages.
- Verification: `PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter pub get` completed; it attempted to update transitive lockfile entries, so `app/pubspec.lock` was reverted because dependency changes are outside this story. `flutter analyze` was run twice and reported only the known unrelated `axisAlignment` deprecation at `app/lib/ui/chat/widgets/input_bar.dart:802` (exit 1 due info-only issue). Targeted `flutter test test/data/local/records_test.dart test/data/repositories/read_repository_test.dart test/data/sync/session_gate_test.dart test/data/sync/sync_service_test.dart test/ui/chat/chat_viewmodel_test.dart` passed (72 tests).
- Acceptance confirmation: different `session_id`s for the same `(epk, roomId)` now have distinct message boxes and session-index keys; old peer+room boxes are not deleted; same-room session rotation resets in-memory state and loads the new scoped box; runtime reachability remains `(epk, roomId)` and does not report live/working while disconnected.
- Discrepancies from design: none.
- Adjacent issues parked: none.

## Review (2026-06-30, fast-lane; HIGH-risk persistence re-key — orchestrator deeply verified)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified the re-key + non-deletion invariants.

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 0214c26` — owned files: `remote_session_ref.dart` (new), `boxes.dart`, `session_index_record.dart`, `home_read_repository.dart`, `session_read_repository.dart`, `session_gate.dart`, `sync_service.dart` (keying only — convergence logic untouched), `chat_viewmodel.dart` (keying), + 5 tests. No collision (protocol files / connection_manager reachability untouched).
- Confirmed `RemoteSessionRef{peerEpk, roomId, sessionId}` single value with `storageKey`; `msgsBoxName(RemoteSessionRef)` → session-scoped `msgs_<epk>__<room>__<sessionId>`; `SessionIndexRecord` gains `sessionId`, `key => ref.storageKey`, `tryFromJson` returns null for legacy records missing `session_id` (defensive — legacy doesn't masquerade as canonical). Reachability stays keyed by `(peerEpk, roomId)` (connection_manager untouched).
- `cd app && flutter test test/data/local/records_test.dart test/data/repositories/read_repository_test.dart test/data/sync/session_gate_test.dart test/data/sync/sync_service_test.dart test/ui/chat/chat_viewmodel_test.dart` (PUB_CACHE set) — 72/72 pass (incl. all turn-projection convergence tests still green — re-key didn't break the working-state invariant).
- `flutter analyze` — only the known-unrelated `axisAlignment` info.
- **Acceptance criteria verified via the rigorous `two session ids on the same room use different boxes and index keys` test**: two session_ids → different boxes (`msgsBoxName isNot`) + different index keys; new session box starts empty (no prior-session leak); old session's messages stay isolated; legacy `msgs_<epk>__main` box NOT deleted (`legacyBox.get(0) == {legacy: true}`); session-id rotation resets in-memory state + loads new box.
