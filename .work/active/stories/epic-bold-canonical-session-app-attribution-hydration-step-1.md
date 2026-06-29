---
id: epic-bold-canonical-session-app-attribution-hydration-step-1
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-canonical-session-app-attribution-hydration
depends_on: [epic-bold-canonical-session-wire-discriminator]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Gate all app server messages by active canonical session

## Current State
```dart
void _onServerMessage(ServerMessage msg, [String? originEpk]) {
  if (originEpk != null && _activeEpk != null && originEpk != _activeEpk) {
    return;
  }
  switch (msg) {
    case AgentChunk(:final inReplyTo, :final delta):
      _chunkBuffer.write(delta);
      _setWorking(true, replyTo: inReplyTo);
    case SessionHistory():
      _applyHistory(msg);
    case QueuedMessageState(:final text):
      _setQueuedText(text?.isNotEmpty == true ? text : null);
  }
}
```

The current boundary only gates late frames by peer (`originEpk`) and sometimes by room in transport. It does not validate the canonical `session_id` before streaming state, working state, queued state, Hive rows, or the session index mutate.

## Target State
```dart
final class ActiveSessionRef {
  const ActiveSessionRef({
    required this.peerEpk,
    required this.roomId,
    required this.sessionId,
  });

  final String peerEpk;
  final String roomId;
  final String sessionId;
}

void _onServerMessage(ServerMessage msg, [String? originEpk]) {
  if (!_acceptOrigin(originEpk)) return;

  final gate = _sessionGate.accepts(msg, _activeSessionRef());
  if (!gate.accepted) {
    debugPrint('[session-gate] drop type=${msg.typeForLog} '
        'room=$_activeRoomId reason=${gate.reason}');
    return;
  }

  switch (msg) {
    case AgentChunk():
    case SessionHistory():
    case QueuedMessageState():
      // only current-session messages reach mutating handlers
  }
}
```

## Implementation Notes
- Add an app-side session gate in `app/lib/data/sync/session_gate.dart` (or equivalent) that consumes the wire-discriminator sibling's `SessionScopedServerMessage` / session-scoped registry rather than re-enumerating message names in `SyncService`.
- Resolve the active expected `session_id` from the active `(epk, roomId)` room snapshot (`ConnectionManager.roomsFor(epk)`), `PairOk.sessionId` bootstrap when available, and the session-index record once Step 3 adds it. If the expected id is unknown, fail closed for session-scoped server messages; `PairOk`, `PairError`, `Pong`, and `Bye` remain non-session-scoped control messages.
- Run the gate immediately after the existing stale-origin peer check and before every mutating branch in `_onServerMessage`: `_chunkBuffer`, `_streaming`, `_setWorking`, `_setQueuedText`, `_upsert`, `_writeCompaction`, `_applyHistory`, session index updates, and pending timer effects.
- Log type, room, and short session-id tails only. Never log message text, images, tool args, or transcript payloads.
- Preserve the existing origin-peer guard; session attribution is an additional correctness boundary, not a replacement for stale channel protection.

## Acceptance Criteria
- [ ] Foreign or missing `session_id` on `session_history` is dropped before `_applyHistory` runs.
- [ ] Foreign or missing `session_id` on chunks/done/tool/queued/error/compaction messages does not touch streaming, working, queued text, Hive rows, pending timers, runtime, or the session index.
- [ ] Same-session messages still follow the existing live-update behavior.
- [ ] Tests cover active session known, active session unknown, missing discriminator, mismatched discriminator, and matched discriminator.
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes.

## Risk
High. The app will intentionally drop legacy session-scoped server pushes until the wire-discriminator sibling is implemented. This is the clean-room fail-closed posture required by the canonical-session epic.

## Rollback
Revert the session-gate call and helper file. This reopens app-side cross-session contamination and should only be used after also rolling back required `session_id` on the wire.
