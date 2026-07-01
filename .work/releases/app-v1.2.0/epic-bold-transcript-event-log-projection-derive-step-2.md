---
id: epic-bold-transcript-event-log-projection-derive-step-2
kind: story
stage: done
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-1]
release_binding: app-v1.2.0
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

- [x] Unit tests cover optimistic submit, echo confirm, timeout, late confirm after timeout, foreign-device message, tool request/result collapse, streaming finalize, compaction row, duplicate server replay idempotence, and session-id filtering.
- [x] `MessageRecord.toChatMessage()` remains a projection target, not the source of reconciliation rules.
- [x] `flutter test test/domain/transcript/transcript_projection_test.dart` passes or is reported with environment blockers.

## Risk

High. This is the hard reconcile rule the store and hydration-replay children depend on. A wrong rule either hides local sends or resurrects stale/foreign history.

## Rollback

Revert the projection reducer/tests. Existing `SyncService` continues to mutate rows directly.

## Implementation Notes
Implemented the pure app transcript projection reconcile reducer in `app/lib/domain/transcript/transcript_projection.dart` and added deterministic coverage in `app/test/domain/transcript/transcript_projection_test.dart`.

Pinned behavior:
- Server-authoritative user/assistant/tool/compaction events form the stable prefix.
- Still-unconfirmed local submissions remain visible as pending after that prefix.
- Same-id authoritative confirmation suppresses pending/failed local state.
- Send timeout marks a local message failed only while no authoritative confirmation exists; late confirmation wins.
- Tool request/result collapse into one projected row.
- Streaming deltas finalize on committed assistant message or `assistant_done`.
- Duplicate replay is idempotent by event/message id.
- Foreign `sessionId` events are ignored by projection filtering.

`MessageRecord` remains untouched; it is still a projection target for later `SyncService` adapter work, not the source of reconcile rules.

Verification attempted:
- `flutter test test/domain/transcript/transcript_projection_test.dart` could not start because the installed Flutter tool attempted to update `/opt/flutter/bin/cache/*` and the cache is read-only in this environment (`Read-only file system`). No tests were weakened or skipped in code; this is an environment/toolchain blocker.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- The projection reducer code in commit `4dd14f1` looks directionally correct, but the deterministic tests do not fully prove two acceptance-critical cases. `ToolEvent.operator ==` ignores `tool`, `args`, `result`, and `error`, so the `tool request and result collapse into one projected tool row` list equality would pass even if the reducer dropped the tool name/args/result. Add explicit field assertions on the projected `ToolEvent`.
- The duplicate replay test says it is idempotent by event id and message id, but the helper generates the same `eventId` for both `confirmed('cli_1', ...)` events. Add a case with distinct event ids and the same message/client id so message-id dedupe is actually verified.

**Important**: none
**Nits**: none

**Notes**: Fast-lane story review with direct commit/file verification. Re-ran `flutter analyze && flutter test` from `app/`, and also tried the targeted `dart test test/domain/transcript/transcript_projection_test.dart`; both fail before analysis/tests start because the installed Flutter/Dart wrapper attempts to write `/opt/flutter/bin/cache/*`, which is read-only. Because this story's value is specifically proving reconcile behavior with deterministic tests, the unproven assertions above are blockers even though the reducer implementation itself appears behavior-preserving on read.

## Bounce resolution (2026-06-29)

Resolved the review blockers by strengthening `app/test/domain/transcript/transcript_projection_test.dart`:

- The tool request/result collapse test now explicitly asserts `tool`, `args`, `status`, `result`, and `error` fields on the projected `ToolEvent`, so it no longer relies on `ToolEvent.operator ==`.
- The duplicate replay test now includes a second `UserMessageConfirmed` with a distinct `eventId` and the same `clientMessageId`, proving message-id dedupe in addition to duplicate-event-id filtering.

Verification:
- `cd app && HOME=/tmp /opt/flutter/bin/cache/dart-sdk/bin/dart analyze` completed with only the existing `axisAlignment` deprecation info in `lib/ui/chat/widgets/input_bar.dart`.
- `cd app && HOME=/tmp /opt/flutter/bin/flutter test test/domain/transcript/transcript_projection_test.dart` could not start because the Flutter tool attempted to write `/opt/flutter/bin/cache/engine.*` and the install is read-only in this environment.

## Review (2026-06-29)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Re-review after bounce. Reviewed commit `551d489`; the requested changes were addressed, not merely recommitted: the tool collapse test now explicitly asserts `tool`, `args`, `status`, `result`, and `error` on the projected `ToolEvent`, and the duplicate replay test now includes a distinct `eventId` with the same `clientMessageId`, proving message-id dedupe beyond duplicate event-id filtering. Acceptance-critical projection cases remain covered in `app/test/domain/transcript/transcript_projection_test.dart`, and `MessageRecord` remains untouched as a later projection target. Verification attempted: `cd app && flutter analyze && flutter test` failed before analysis/tests because `/opt/flutter/bin/cache/*` is read-only; fallback `HOME=/tmp /opt/flutter/bin/cache/dart-sdk/bin/dart analyze` completed with only the pre-existing `axisAlignment` deprecation info, and fallback `dart test --no-pub test/domain/transcript/transcript_projection_test.dart` was blocked by a pub.dev proxy 403 during build hooks. No tests were weakened or skipped.
