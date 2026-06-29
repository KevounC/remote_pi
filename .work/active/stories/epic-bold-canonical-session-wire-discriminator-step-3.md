---
id: epic-bold-canonical-session-wire-discriminator-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-canonical-session-wire-discriminator
depends_on: [epic-bold-canonical-session-wire-discriminator-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Drop foreign server messages in the app before any state mutation

## Current State
```dart
case SessionHistory():
  // ignore: discarded_futures
  _applyHistory(msg);

Future<void> _applyHistory(SessionHistory h) async {
  final epk = _activeEpk;
  if (epk == null) return;
  final box = await _boxes.msgsBox(epk, _activeRoomId);
  // reconciles active box to h.events
}
```

`WsTransport` also accepts legacy no-room envelopes unconditionally, so an outer frame without room attribution can still reach `SyncService` and mutate whichever `(epk, room)` is currently active.

## Target State
```dart
final gate = _sessionGate.accepts(msg, _activeSessionRef());
if (!gate.accepted) {
  debugPrint('[session-gate] drop type=${msg.type} room=${_activeRoomId} reason=${gate.reason}');
  return;
}

case SessionHistory():
  _applyHistory(msg); // only current-session history reaches here
```

## Implementation Notes
- Track active expected session id from `PairOk.sessionId` and `RoomInfo.sessionId` for the active `(epk, roomId)`.
- If the active room has no session id yet, session-scoped server messages are unsafe and should be dropped except for `pair_ok` bootstrap.
- Gate at the top of `_onServerMessage`, before `AgentChunk`, `AgentDone`, `QueuedMessageState`, `UserInput`, tool messages, `ErrorMessage`, `Compaction`, `_setWorking`, `_setQueuedText`, `_upsert`, `_writeCompaction`, or `_applyHistory` run.
- Remove `WsTransport`'s legacy no-room unconditional route in the clean-room path; no-room envelopes should not bypass session attribution.
- High-water `session_started_at` remains useful for replay ordering inside the same session, but it is not an identity check.

## Acceptance Criteria
- [ ] Regression test: active session A has rows; a foreign session B `session_history` arrives with a different `session_id`; A's Hive box and session index remain unchanged.
- [ ] Missing `session_id` on `session_history` is dropped and does not clear/overwrite the active box.
- [ ] Foreign chunks/done/tool/queued/error/compaction messages do not affect streaming, working, queued text, persisted rows, or session index.
- [ ] Legitimate same-session reconnect replay with equal `session_id` still hydrates idempotently.
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes.

## Risk
High. A missing expected session id during bootstrap could make the app appear idle/disconnected by dropping legitimate frames. Bootstrap from `pair_ok`/room metadata must be deterministic.

## Rollback
Disable the app gate via one internal seam, then revert the protocol fields and SyncService call sites. Rolling back reopens contamination and should be treated as an emergency-only fork-private regression.
