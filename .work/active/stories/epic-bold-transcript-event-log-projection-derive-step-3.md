---
id: epic-bold-transcript-event-log-projection-derive-step-3
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Route `SyncService` live writes through the projection seam

**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction
**Files**: `app/lib/data/sync/sync_service.dart`, `app/lib/data/local/records/message_record.dart`, `app/test/data/sync/sync_service_test.dart`

## Current State

```dart
case AgentChunk(:final inReplyTo, :final delta):
  _chunkBuffer.write(delta);
  _setWorking(true, replyTo: inReplyTo);

case SessionHistory():
  _applyHistory(msg); // computes desired rows and reconciles the Hive box
```

Live events, optimistic pending rows, timeout failures, and history replay are separate mutation paths.

## Target State

```dart
void _appendTranscriptEvent(TranscriptEvent event) {
  if (event.sessionId != _activeSessionId) return;
  _eventBuffer = appendDeduped(_eventBuffer, event);
  final next = deriveTranscriptProjection(sessionId: _activeSessionId, events: _eventBuffer);
  _writeProjectionDiff(next);
}

case AgentChunk(:final inReplyTo, :final delta):
  _appendTranscriptEvent(AssistantDeltaReceived(...));

case SessionHistory():
  for (final event in historyToTranscriptEvents(msg, sessionId: _activeSessionId)) {
    _appendTranscriptEvent(event);
  }
```

Hive `MessageRecord` rows remain materialized output for this story; the append-only Hive event store is the next child feature.

## Implementation Notes

- Keep the existing `msgs:<epk>:<room>` boxes, `SessionReadRepository`, and UI read path intact.
- `_applyHistory` may remain as a compatibility adapter name, but it must convert history to events and re-project instead of owning reconciliation semantics.
- Pending-send timers become event producers (`UserMessageFailed`) until the store child persists timer-origin events.
- Keep `_writeChain` serialization for projection diff writes.
- Use canonical `session_id` when present; otherwise isolate a named compatibility shim that maps the active `(epk, room)` to a temporary session id.

## Acceptance Criteria

- [ ] Existing `app/test/data/sync/sync_service_test.dart` remains green.
- [ ] New tests prove history replay does not delete local pending events and duplicate replay emits no Hive churn.
- [ ] New tests prove late authoritative echo after timeout converges according to the step-2 projection rule; if current failure-row behavior is deliberately preserved for compatibility, record that rationale before review.
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes.

## Risk

High. This touches the mobile writer's lifecycle and can cause message loss, duplicate bubbles, stale working state, or Hive churn if the projection diff is wrong.

## Rollback

Revert `SyncService` to direct `_upsert` / `_applyHistory` mutation. Projection contract/tests from steps 1-2 can remain unused.
