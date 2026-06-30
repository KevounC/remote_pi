---
id: epic-bold-transcript-event-log-store-step-2
kind: story
stage: done
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation

- Live transcript paths now append `TranscriptEvent` records to `TranscriptEventStore` first, then read the stored session log, derive `TranscriptProjection`, and rewrite the disposable `msgs` projection under `_writeChain`.
- `sendMessage`, `UserInput`, assistant chunks/done/messages, tool request/result, cancellation/error terminals, and compaction now flow through event append + projection materialization instead of treating `MessageRecord` as transcript truth.
- Pending-send timeout and send-error backstops append `UserMessageFailed`; a later `UserMessageConfirmed` with the same client id is retained in the event log and wins in the derived projection.
- `SessionHistory` replay is converted to deterministic server-authoritative transcript events and appended/deduped through the event store; replay does not delete local unseen event-log entries.
- Tests cover success, timeout, late-confirm-after-timeout, cancel/error, compaction, reconnect replay, session switch filtering, duplicate replay/no churn, and deleting/rebuilding the `msgs` box from the stored event log.
- Confirmed `msgs` is disposable: clearing it and constructing a fresh `SyncService` rebuilds the same ordered projection from `TranscriptEventStore`.

## Rollback

Restore `SyncService` direct `_upsert`/`_applyHistory` writes and leave the event store unused. Because projection boxes were not deleted as part of rollback, the old row-based cache remains available.

## Review

Approved (2026-06-30) with HIGH-risk convergence verification. Independently
re-ran: whole-app `flutter analyze` → only known `axisAlignment` info; full
`flutter test` → 597/597 (incl. sync_service 56/56). Commit `657bf3c` scoped to
app only (sync_service.dart refactor + message_record + boxes + sync_service_test
+ pubspec.lock transitive update + story .md); no cross-subproject collision.

Projection switchover verified: `SyncService` appends `TranscriptEvent` to
`TranscriptEventStore` FIRST, then reads the stored session log → derives
`TranscriptProjection` → rewrites the disposable `msgs` projection under
`_writeChain`. `MessageRecord` boxes are no longer transcript truth (derived).
Convergence invariants verified directly in tests: same-session reconnect
replay hydrates idempotently; re-applying IDENTICAL SessionHistory = no box churn;
pending-send timeout appends `UserMessageFailed` + late `UserMessageConfirmed`
wins in the derived projection; `session_history` replay appends/dedupes without
deleting unseen local events; `msgs` rebuildable from event log (clearing +
fresh SyncService recovers the same ordered projection). Working/streaming
convergence covered across success/timeout/late-confirm/cancel-error/compaction/
reconnect-replay/session-switch. The `pubspec.lock` change is a benign transitive
`meta`/`test_api` update from `flutter pub get`.
