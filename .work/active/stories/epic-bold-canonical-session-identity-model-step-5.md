---
id: epic-bold-canonical-session-identity-model-step-5
kind: story
stage: implementing
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: [epic-bold-canonical-session-identity-model-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
