---
id: epic-bold-transcript-event-log-projection-derive-step-2
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Prove the app reconcile projection with deterministic tests

**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle convergence
**Files**: `app/lib/domain/transcript/transcript_projection.dart`, `app/test/domain/transcript/transcript_projection_test.dart`, `app/lib/data/local/records/message_record.dart`

## Current State

```dart
// app/lib/data/sync/sync_service.dart
await _upsert(MsgRole.user, id, (seq, existing) => existing != null
    ? existing.copyWith(pending: false)
    : MessageRecord(id: id, seq: seq, role: MsgRole.user, text: text, ts: DateTime.now()));

// _applyHistory builds `desired` rows and reconciles Hive keys directly.
```

`SyncService` owns the reconciliation rules, pending-send semantics, streaming buffer, and Hive writes in one mutable service.

## Target State

A pure reducer proves the transcript projection without storage or transport:

```dart
final projection = deriveTranscriptProjection(
  sessionId: activeSessionId,
  events: eventLog,
);

expect(projection.messages, [
  ProjectedUserMessage(id: 'cli_1', text: 'hello', pending: false),
  ProjectedAssistantMessage(replyTo: 'cli_1', text: 'done'),
]);
expect(projection.turn.status, TranscriptTurnStatus.idle);
```

Pinned reconcile rules:

```dart
// local pending remains visible while absent from authoritative replay
submitted('cli_1', 'hello'), serverReplay(user('server_old', 'older'))
=> [older confirmed, hello pending]

// authoritative same id confirms in place
submitted('cli_1', 'hello'), confirmed('cli_1', 'hello')
=> [hello confirmed]

// timeout is suppressed by later authoritative confirmation
submitted('cli_1', 'hello'), failed('cli_1', 'send_timeout'), confirmed('cli_1', 'hello')
=> [hello confirmed]
```

## Implementation Notes

- Keep reducer pure and deterministic: no Hive boxes, timers, `ConnectionManager`, or Flutter context.
- Projection orders by event-log append order, with server replay forming the authoritative prefix and still-unconfirmed local submitted events retained when absent from replay.
- Tool request/result collapse into one projected tool row.
- Streaming deltas project into `streaming` until assistant commit/done or a terminal failure/cancel event closes the turn.
- `working` must converge false after success, send failure, cancellation/error, compaction completion, reconnect replay with idle evidence, and session switch via `sessionId` filtering.

## Acceptance Criteria

- [ ] Unit tests cover optimistic submit, echo confirm, timeout, late confirm after timeout, foreign-device message, tool request/result collapse, streaming finalize, compaction row, duplicate server replay idempotence, and session-id filtering.
- [ ] `MessageRecord.toChatMessage()` remains a projection target, not the source of reconciliation rules.
- [ ] `flutter test test/domain/transcript/transcript_projection_test.dart` passes.

## Risk

High. This is the hard reconcile rule the store and hydration-replay children depend on. A wrong rule either hides local sends or resurrects stale/foreign history.

## Rollback

Revert the projection reducer/tests. Existing `SyncService` continues to mutate rows directly.
