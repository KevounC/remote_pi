---
id: epic-bold-canonical-session-app-attribution-hydration-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-canonical-session-app-attribution-hydration
depends_on: [epic-bold-canonical-session-app-attribution-hydration-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
