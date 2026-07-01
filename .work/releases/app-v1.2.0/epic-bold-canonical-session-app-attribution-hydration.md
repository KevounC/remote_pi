---
id: epic-bold-canonical-session-app-attribution-hydration
kind: feature
stage: done
tags: [refactor, bold, app, security]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-wire-discriminator]
release_binding: app-v1.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — app attribution & hydration fail-closed

## Brief
The app half of the contamination fix. Require `session_id` on every
chat-bearing ServerMessage; drop + log when absent or mismatched. Retire the
"legacy no-room routes unconditionally" path in `ws_transport.dart`. `_onServerMessage`
validates the embedded `session_id` against the active session before accepting.
`_applyHistory` refuses a `session_history` whose `session_id` != active session
— so a foreign history can never replace the local transcript box (the direct
fix for "session B showed only session A's stray turn"). Lift room/session demux
from transport-optimization to correctness boundary.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: consumer of the wire discriminator (the `session_id` field) and
  precondition for the transcript-event-log epic's replay-as-projection.

## Foundation references
- Evidence: `app/lib/data/transport/ws_transport.dart:63-103`,
  `app/lib/data/sync/sync_service.dart:409-435` (epk-only gate),
  `:497-535` (active-box write), `:671-760` (`_applyHistory` replaces).

<!-- /agile-workflow:refactor-design pins the validation sites + failure
semantics. -->

## Design decisions
- **Refactor-lane judgment**: this app slice changes clean-room behavior (legacy/missing `session_id` chat frames are dropped), but stays in the bold `[refactor]` lane by explicit autopilot/operator direction because it restores the designed-then-dropped session discriminator and removes a contamination class in a fork-private branch.
- **Attribution boundary**: app-side validation happens before `SyncService` mutates streaming buffers, working/queued state, pending timers, Hive message boxes, runtime records, or session-index records. A session-scoped server push without the active canonical `session_id` is unsafe and is dropped.
- **Expected session source**: the active expected `session_id` comes from the canonical room/session metadata already exposed as `RoomInfo.sessionId` and `PairOk.sessionId`, then is carried into a single `RemoteSessionRef`/`ActiveSessionRef` value for persistence and sync. `session_started_at` remains high-water metadata inside a session, not an identity substitute.
- **Transport posture**: `WsTransport` still demuxes by relay room, but the legacy no-room unconditional route is retired. Transport enforces room attribution; `SyncService` enforces canonical session attribution. Neither parses payload bodies for relay-level session routing.
- **Hydration posture**: `session_history` is replay input. Same-session replay appends/dedupes transcript events and updates a projection; it does not replace the active box with whatever the latest history payload contained. This coordinates with `epic-bold-transcript-event-log-projection-derive` and keeps the implementation compatible with patchbay's future event-log source.
- **Patchbay migration posture**: the app treats `session_id` as opaque equality data and keeps storage/key helpers centralized. No cwd hash, room naming convention, or fork-specific path becomes semantic identity.

## Refactor Overview
The app currently has two fail-open layers and one destructive/replacement reducer:

- `WsTransport` drops room-mismatched envelopes but explicitly routes legacy no-room envelopes unconditionally.
- `SyncService._onServerMessage` gates late frames by peer origin only; it accepts every decoded `ServerMessage` for the active room before streaming, working, queued state, Hive, and session-index mutations.
- `SyncService._applyHistory` is idempotent against identical replay, but it still reconciles the active message box to the incoming history. A foreign `session_history` that reaches this function can overwrite the viewed session.

The target is a two-boundary app attribution model: transport drops missing/mismatched rooms, then sync drops missing/mismatched canonical sessions before any state mutation. Hydration for accepted same-session history becomes replay through the transcript-event seam rather than replacement of the active box.

Scope probe / scan rationale: direct-read only. The target was a bounded app module (`ws_transport.dart`, `sync_service.dart`, `LocalBoxes`, `SessionIndexRecord`, `MessageRecord`, `session_state.dart`) plus explicitly named sibling designs. No exploratory sub-agent was dispatched because this nested delegated worker has no subagent tool exposed and the relevant files/tests were already bounded. Scan findings by lens: code smell (`_applyHistory` replacement reducer and `_onServerMessage` mutation-before-session-attribution), missing abstraction (no `ActiveSessionRef`/session gate), pattern/naming drift (`session_started_at`, `(epk, room)`, and `session_id` compete as session concepts), dead weight (legacy no-room transport compatibility path).

Cycle check: `.work/bin/work-view --blocking` is unavailable in this checkout (the `.work/bin/` directory is empty). Manual frontmatter check found a linear chain with no cycle: step 1 depends on `epic-bold-canonical-session-wire-discriminator`; steps 2-4 each depend on the prior step; no existing item depends on these new ids.

## Refactor Steps

### Step 1: Gate all app server messages by active canonical session
**Priority**: High
**Risk**: High
**Source Lens**: fail-fast boundary / missing abstraction
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/sync/session_gate.dart`, `app/lib/protocol/protocol.dart`, `app/lib/data/transport/connection_manager.dart`, `app/test/data/sync/sync_service_test.dart`
**Story**: `epic-bold-canonical-session-app-attribution-hydration-step-1`

**Current State**:
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
  }
}
```

**Target State**:
```dart
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
```

**Implementation Notes**:
- Consume the wire-discriminator sibling's session-scoped server-message registry/interface; do not duplicate a second message-name list in `SyncService`.
- Resolve active expected `session_id` from `RoomInfo.sessionId`, `PairOk.sessionId`, and later the session-scoped index record. Unknown expected session id fails closed for session-scoped pushes.
- Gate before `_chunkBuffer`, `_streaming`, `_setWorking`, `_setQueuedText`, `_upsert`, `_writeCompaction`, `_applyHistory`, pending timers, runtime writes, and session-index writes.
- Preserve the existing origin-peer guard as a separate stale-channel defense.

**Acceptance Criteria**:
- [ ] Build passes.
- [ ] Tests pass.
- [ ] Foreign or missing `session_id` on `session_history` is dropped before `_applyHistory`.
- [ ] Foreign chunks/done/tool/queued/error/compaction messages do not mutate streaming, working, queued text, Hive rows, or session index.
- [ ] Same-session messages preserve existing behavior.

**Rollback**: Revert the session gate and helper. This reopens the contamination vector and should only accompany a rollback of the required wire discriminator.

---

### Step 2: Retire the transport legacy no-room fail-open route
**Priority**: High
**Risk**: Medium
**Source Lens**: dead weight / fail-fast boundary
**Files**: `app/lib/data/transport/ws_transport.dart`, app transport tests
**Story**: `epic-bold-canonical-session-app-attribution-hydration-step-2`

**Current State**:
```dart
final senderRoom = frame['room'] as String?;
if (senderRoom != null && senderRoom != transport._activeRoom) {
  return;
}
// Legacy Pis without `room` route unconditionally.
transport._queue.add(bytes);
```

**Target State**:
```dart
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
```

**Implementation Notes**:
- Keep control frames on `controlFrames`; only chat-bearing `{peer, room, ct}` envelopes become fail-closed on missing room.
- Extract the post-auth demux into a tiny deterministic helper if needed for tests.
- Do not teach transport to parse `session_id`; session attribution belongs to `SyncService`.

**Acceptance Criteria**:
- [ ] Build passes.
- [ ] Tests pass.
- [ ] Missing-room envelopes are dropped and never reach `SyncService`.
- [ ] Active-room envelopes still deliver unchanged; control frames still emit.

**Rollback**: Restore the no-room enqueue branch, knowingly restoring legacy fail-open behavior.

---

### Step 3: Key app persistence by canonical session id
**Priority**: High
**Risk**: High
**Source Lens**: naming inconsistency / persistence key consolidation
**Files**: `app/lib/data/local/boxes.dart`, `app/lib/data/local/records/session_index_record.dart`, `app/lib/data/local/records/message_record.dart`, `app/lib/data/repositories/session_read_repository.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`
**Story**: `epic-bold-canonical-session-app-attribution-hydration-step-3`

**Current State**:
```dart
static String msgsBoxName(String epk, String roomId) =>
    'msgs_${toAppEpk(epk)}__$roomId';

static String sessionKey(String epk, String roomId) => '$epk:$roomId';
```

**Target State**:
```dart
final class RemoteSessionRef {
  final String peerEpk;
  final String roomId;
  final String sessionId;
  String get storageKey => '$peerEpk:$roomId:$sessionId';
}

static String msgsBoxName(RemoteSessionRef ref) =>
    'msgs_${toAppEpk(ref.peerEpk)}__${ref.roomId}__${_safe(ref.sessionId)}';
```

**Implementation Notes**:
- Centralize all session key construction in one value/helper. Do not scatter `$epk:$room:$session` string building.
- Keep reachability (`ConnectionManager.isRoomLive` / `isRoomWorking`) keyed by `(epk, roomId)`; only transcript/session persistence moves to canonical session id.
- Ignore old `(epk, room)` boxes rather than deleting or in-place migrating them. The canonical session can hydrate from the Pi via `session_sync`.
- A `session_id` rotation on the same room resets active in-memory turn state and opens the new session-scoped box.

**Acceptance Criteria**:
- [ ] Build passes.
- [ ] Tests pass.
- [ ] Two session ids on the same `(epk, room)` never share a message box or session-index row.
- [ ] Old boxes remain on disk and are not destructively migrated.
- [ ] Room reachability still follows `(peer, room)` snapshots.

**Rollback**: Restore `(epk, roomId)` persistence keys. Leave any new session-scoped boxes on disk for recovery; do not delete caches during rollback.

---

### Step 4: Hydrate by replaying session history through the transcript event seam
**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle convergence / missing abstraction
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/domain/transcript/transcript_event.dart`, `app/lib/domain/transcript/transcript_projection.dart`, `app/test/data/sync/sync_service_test.dart`, `app/test/domain/transcript/transcript_projection_test.dart`
**Story**: `epic-bold-canonical-session-app-attribution-hydration-step-4`

**Current State**:
```dart
final rows = _convertHistory(h.events);
final desired = <MessageRecord>[
  for (var i = 0; i < rows.length; i++) rows[i].copyWith(seq: i),
  for (var j = 0; j < preserved.length; j++)
    preserved[j].copyWith(seq: rows.length + j),
];
// Reconcile the box to desired.
```

**Target State**:
```dart
for (final event in historyToTranscriptEvents(h, sessionId: ref.sessionId)) {
  _appendTranscriptEvent(event);
}
final projection = deriveTranscriptProjection(
  sessionId: ref.sessionId,
  events: _transcriptEvents,
);
await _writeProjectionDiff(ref, projection);
```

**Implementation Notes**:
- Step 1 ensures only same-session history reaches `_applyHistory`; keep a defensive check inside `_applyHistory` for direct tests/future callers.
- Convert history events to deterministic `TranscriptEvent`s, append/dedupe, then write a projection diff. Reconnect replay is idempotent replay, not destructive replacement.
- Preserve local pending events; late authoritative confirmation wins over timeout/failure per the transcript-event-log sibling design.
- `session_started_at` remains a same-session high-water guard and must never substitute for `session_id` equality.

**Acceptance Criteria**:
- [ ] Build passes.
- [ ] Tests pass.
- [ ] Same-session reconnect replay is idempotent and does not duplicate or drop messages.
- [ ] Replay that omits older local rows does not delete them merely because they are absent from the payload.
- [ ] Foreign `session_history` is covered by a regression test proving the active session box/index remain unchanged.

**Rollback**: Revert `_applyHistory` to the current diff-to-desired reducer while keeping session gating. Log that hydration is temporarily same-session replacement rather than replay.

## Implementation Order
1. `epic-bold-canonical-session-app-attribution-hydration-step-1` (depends on `epic-bold-canonical-session-wire-discriminator`)
2. `epic-bold-canonical-session-app-attribution-hydration-step-2` (depends on step 1)
3. `epic-bold-canonical-session-app-attribution-hydration-step-3` (depends on step 2)
4. `epic-bold-canonical-session-app-attribution-hydration-step-4` (depends on step 3)

## Atomic / rollback notes
No step is intentionally irreversible. Step 3 is the persistence-key switchover and Step 4 is the hydration-reducer switchover; keep each in its own implementation commit so either can roll back without removing the Step 1 session gate.

## Run notes
- No `.agents/skills/refactor-conventions/` or pattern-skill catalog exists; the default refactor-design lenses were used.
- Design-time advisory review/subagent was skipped because this delegated Pi sub-agent context exposes no `subagent`/peer-review tool. The design records the skipped dispatch rationale and concrete acceptance tests instead.
- Fork-private clean-room behavior is intentional: legacy no-room or no-session chat frames drop fail-closed rather than preserving compatibility that keeps the contamination class alive.
