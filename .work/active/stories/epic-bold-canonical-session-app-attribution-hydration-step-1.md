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

## Implementation notes
- Files changed: `app/lib/data/sync/session_gate.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/protocol/protocol.dart`, `app/test/data/sync/session_gate_test.dart`, `app/test/data/sync/sync_service_test.dart`.
- Tests added: direct `SessionGate` coverage for non-session controls, active-session unknown, missing discriminator, mismatch, and match; SyncService regressions for foreign/missing `session_history` and foreign/same-session chunks.
- Discrepancies from design: concurrent turn-state-machine work had already added the `SyncService` session-gate field and helper skeleton before this commit; this story wires the helper into `_onServerMessage` and adds the concrete app gate implementation/tests. Existing tests still use direct constructors, so the test fake injects the active `sessionId` unless a test deliberately uses `pushRaw` to exercise missing/foreign discriminators.
- Adjacent issues parked: none.
- Verification: `dart format` ran on touched app files; `HOME=/tmp/remote-pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze ...` on touched files reported one unrelated warning from concurrent `_transcriptEventStore` work in `sync_service.dart`; `flutter analyze` and `flutter test test/data/sync/session_gate_test.dart test/data/sync/sync_service_test.dart` could not start because `/opt/flutter/bin/cache` is read-only; `dart test` could not run because pub.dev access was blocked by proxy 403.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- The implementation is not committed. `git log --oneline -i --grep="epic-bold-canonical-session-app-attribution-hydration-step-1" --all` found no implementation commit, while `app/lib/data/sync/session_gate.dart`, `app/test/data/sync/session_gate_test.dart`, and related app files are currently dirty/untracked in the working tree.
- Required app verification is not green. `flutter analyze && flutter test` cannot start in this environment because `/opt/flutter/bin/cache` is read-only; nearest `dart analyze` on touched app files exits nonzero on an unused `_transcriptEventStore` warning, and `dart test` is blocked by pub.dev proxy 403.

**Important**: none
**Nits**: none

**Notes**: Review inspected the dirty working-tree implementation enough to confirm the intended gate is placed before the `SyncService` mutating switch and direct tests cover missing/foreign `session_history` and chunks. However, the review skill requires a committed review target and honest verification evidence; this item cannot advance while its implementation is uncommitted and verification is unresolved. Commit the app implementation (or revert the dirty work), rerun the closest available app checks, and return to `stage: review`.
