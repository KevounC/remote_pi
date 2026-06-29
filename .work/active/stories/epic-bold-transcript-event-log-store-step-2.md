---
id: epic-bold-transcript-event-log-store-step-2
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Make app projections rebuildable outputs of the event store

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / lifecycle convergence  
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/local/records/message_record.dart`, `app/lib/data/local/boxes.dart`, `app/test/data/sync/sync_service_test.dart`

## Current State

```dart
await _upsert(MsgRole.user, id, (seq, _) => MessageRecord(
  id: id,
  seq: seq,
  role: MsgRole.user,
  text: text,
  pending: true,
  ts: now,
));

case SessionHistory():
  _applyHistory(msg); // computes desired rows and mutates/deletes the msgs box
```

## Target State

```dart
Future<void> _appendTranscriptEvents(Iterable<TranscriptEvent> events) async {
  final key = _activeTranscriptKeyOrNull();
  if (key == null) return;
  final result = await _eventStore.appendAll(key, events);
  if (result.appended == 0) return;
  final log = await _eventStore.readSession(key);
  final projection = deriveTranscriptProjection(
    sessionId: key.sessionId,
    events: log,
  );
  await _rewriteMessageProjection(key, projection);
}
```

## Implementation Notes

- Live paths (`sendMessage`, `UserInput`, `AgentChunk`, `AgentDone`, tool request/result, cancelled/error, compaction) append the sibling-defined `TranscriptEvent` variants first. `MessageRecord` writes happen only through projection materialization.
- Pending-send timers become event producers: timeout appends `UserMessageFailed`; a late `UserMessageConfirmed` with the same client id wins in the projection per the sibling reconcile rule.
- `SessionHistory` is converted to deterministic server-authoritative events and passed to `appendAll`; it does not compute a replacement `desired` list itself.
- Keep `_writeChain` around event append + projection writes.
- Store-derived projection may rewrite or diff the `msgs` box, but that box is explicitly disposable.

## Acceptance Criteria

- [ ] `SyncService` no longer treats `MessageRecord` boxes as transcript truth; they are derived from `TranscriptEventStore`.
- [ ] `session_history` replay appends/dedupes events and does not delete local unseen events from the event log.
- [ ] Duplicate replay produces zero new events and no visible message churn.
- [ ] Deleting/rebuilding the `msgs` projection from the stored event log recovers the same ordered messages.
- [ ] Working/streaming convergence tests cover success, timeout, late confirm after timeout, cancel/error, compaction, reconnect replay, and session switch filtering.
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes.

## Rollback

Restore `SyncService` direct `_upsert`/`_applyHistory` writes and leave the event store unused. Because projection boxes were not deleted as part of rollback, the old row-based cache remains available.
