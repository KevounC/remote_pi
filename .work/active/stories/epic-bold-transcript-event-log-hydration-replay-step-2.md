---
id: epic-bold-transcript-event-log-hydration-replay-step-2
kind: story
stage: review
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-hydration-replay-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 2: Replace `_applyHistory` destructive reconcile with append/dedupe replay

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / lifecycle convergence  
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/local/records/message_record.dart`, `app/lib/domain/contracts/transcript_event_store.dart`, `app/test/data/sync/sync_service_test.dart`

## Current State

```dart
final rows = _convertHistory(h.events);
final historyIds = {for (final r in rows) _key(r.role, r.id)};
final preserved = <MessageRecord>[];
for (final v in box.values) {
  final r = MessageRecord.fromJson(_coerce(v));
  if (r.role == MsgRole.user && r.pending && !historyIds.contains(_key(r.role, r.id))) {
    preserved.add(r);
  }
}
final desired = <MessageRecord>[
  for (var i = 0; i < rows.length; i++) rows[i].copyWith(seq: i),
  for (var j = 0; j < preserved.length; j++) preserved[j].copyWith(seq: rows.length + j),
];
// Deletes any box key beyond desired.length and rewrites mismatched rows.
```

## Target State

```dart
Future<void> _replayHistory(SessionHistory history) async {
  final key = _activeTranscriptKeyOrNull();
  if (key == null) return;
  if (_isStaleHistory(history.sessionStartedAt)) return;

  final replayEvents = sessionHistoryToTranscriptEvents(
    history: history,
    sessionId: key.sessionId,
  );
  await _appendTranscriptEventsAndProject(key, replayEvents);
  _acceptHistoryBoundary(history.sessionStartedAt);
}
```

```dart
Future<void> _appendTranscriptEventsAndProject(
  TranscriptSessionKey key,
  Iterable<TranscriptEvent> events,
) async {
  final result = await _eventStore.appendAll(key, events);
  if (result.appended == 0) return;
  final projection = deriveTranscriptProjection(
    sessionId: key.sessionId,
    events: await _eventStore.readSession(key),
  );
  await _rewriteMessageProjectionFromLog(key, projection);
}
```

## Implementation Notes

- `_applyHistory` may remain as a compatibility wrapper named `_replayHistory` during the transition, but it must not call `_convertHistory` or delete rows because a replay omitted them.
- Keep `_writeChain` around event append + projection cache writes; replay is still a serialized persistence operation.
- Update `_acceptedSessionStartedAtHighWater` only after accepting the batch. It rejects stale session boundaries but is not a transcript identity.
- `truncated: true` and empty batches append fewer/no events; they never delete earlier local log entries.
- Pending timeouts become `UserMessageFailed` events from the store sibling; a later `UserMessageConfirmed` from replay wins in projection and suppresses stale failure UI.

## Acceptance Criteria

- [x] `SessionHistory` handling appends/dedupes events in `TranscriptEventStore`; `MessageRecord` rows are only a projection cache.
- [x] A replay missing an existing local event does not delete that event from the event log or active projection.
- [x] Duplicate replay appends zero events and emits no message-box churn.
- [x] Late authoritative replay of a timed-out message confirms it and suppresses the timeout failure projection.
- [x] Stale `session_started_at` is rejected before store append; same-boundary replay is accepted/idempotent.
- [x] Targeted app sync tests pass: `flutter test test/data/sync/sync_service_test.dart`.

## Implementation

- Replaced the remaining `_applyHistory` path with `_replayHistory`, converting `SessionHistory` through the step-1 replay adapter and appending/deduping those events in `TranscriptEventStore` before rebuilding the disposable `MessageRecord` projection cache.
- Kept replay append + projection materialization inside `_writeChain`, and moved the stale `session_started_at` check into that serialized boundary so racing stale replays are rejected before `appendAll`.
- Preserved append-only replay semantics: replays that omit existing local/logged events do not delete them, duplicate replay appends zero events and produces no message-box churn, and same-boundary replay remains accepted/idempotent.
- Added replay-specific tests for late authoritative confirmation after a send timeout and for stale-boundary rejection before source-log append. Existing projection tests cover `MessageRecord` as a rebuildable cache.
- Verification: targeted `flutter test test/data/sync/sync_service_test.dart` passed `60` tests; full `flutter test` passed `610` tests; `flutter analyze` reported only the known unrelated `axisAlignment` deprecation at `app/lib/ui/chat/widgets/input_bar.dart:802`.

## Rollback

Restore `_applyHistory` to `_convertHistory` + diffed row reconcile. The event store/adapter from step 1 can remain unused.
