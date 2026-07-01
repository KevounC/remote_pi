---
id: epic-bold-transcript-event-log-hydration-replay-step-1
kind: story
stage: done
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-store]
release_binding: app-v1.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 1: Add deterministic app `SessionHistory` replay adapter

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / single source of truth  
**Files**: `app/lib/data/sync/session_history_replay.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/domain/transcript/transcript_event.dart`, `app/test/data/sync/session_history_replay_test.dart`

## Current State

```dart
// app/lib/data/sync/sync_service.dart
case SessionHistory():
  // ignore: discarded_futures
  _applyHistory(msg);

List<MessageRecord> _convertHistory(List<SessionHistoryEvent> events) {
  final out = <MessageRecord>[];
  // Converts directly to mutable projection rows.
}
```

## Target State

```dart
List<TranscriptEvent> sessionHistoryToTranscriptEvents({
  required SessionHistory history,
  required String sessionId,
}) => [
  for (final event in history.events)
    switch (event) {
      UserInputEvt() => UserMessageConfirmed(
          eventId: serverReplayEventId(sessionId, 'user_input', event.id, event.ts),
          sessionId: sessionId,
          ts: DateTime.fromMillisecondsSinceEpoch(event.ts),
          clientMessageId: event.id,
          text: event.text,
          image: event.image == null ? null : MessageImage(data: event.image!.data, mime: event.image!.mime),
        ),
      AgentMessageEvt() => AssistantMessageCommitted(...),
      ToolRequestEvt() => ToolRequested(...),
      ToolResultEvt() => ToolFinished(...),
      CompactionEvt() => CompactionRecorded(...),
    },
];
```

## Implementation Notes

- Keep the adapter in `data/sync`: protocol DTOs are infrastructure; domain projection consumes only `TranscriptEvent`.
- `serverReplayEventId` must ignore `in_reply_to` request ids and use stable event facts, so identical replay batches dedupe.
- Convert `UserInputEvt` to `UserMessageConfirmed`, not `UserMessageSubmitted`; the server is authoritative and confirms any matching optimistic event.
- Preserve image, tool result/error, compaction token count, and assistant usage if present on the wire.
- Fail fast on missing active `session_id`; use a narrowly named compatibility shim only while canonical-session implementation is in flight.

## Acceptance Criteria

- [ ] Adapter returns only `TranscriptEvent` values and imports no Hive/UI/ViewModel code.
- [ ] Identical `SessionHistory` payloads produce identical `eventId`s regardless of request `in_reply_to`.
- [ ] `UserInputEvt` confirms matching optimistic messages by client id.
- [ ] Tests cover user/image, assistant, tool request/result, compaction, duplicate id stability, and unknown/unsupported event handling.
- [ ] Targeted app test passes: `flutter test test/data/sync/session_history_replay_test.dart`.

## Rollback

Remove the adapter/tests. Existing `_convertHistory` row conversion remains until step 2 swaps callers.

## Implementation

- Adapter design: added `app/lib/data/sync/session_history_replay.dart` as a pure data/sync protocol-to-domain adapter. `SyncService._applyHistory` now calls `sessionHistoryToTranscriptEvents(...)`; `TranscriptEvent` no longer owns the `SessionHistoryEvent` conversion seam.
- Determinism guarantees: replay event ids are `server:<session_id>:<history-type>:<stable-key>:<ts>` and deliberately ignore the outer `SessionHistory.inReplyTo` request id. User history replays produce `UserMessageConfirmed` with `clientMessageId` set to the wire event id, so matching optimistic submissions confirm by client id. Duplicate identical server facts produce identical event ids for store dedupe.
- Test coverage: added `app/test/data/sync/session_history_replay_test.dart` covering user input with image, assistant message replay, tool request/result replay, compaction token replay, request-id-independent event ids, duplicate-id stability, unsupported future history event rejection, and missing canonical session id fail-fast behavior.
- Verification: targeted `flutter test test/data/sync/session_history_replay_test.dart` passed 8/8. Full `flutter test` passed 608/608. `flutter analyze` reported only the known unrelated `axisAlignment` deprecation at `lib/ui/chat/widgets/input_bar.dart:802`.
- Discrepancies from design: assistant usage is not present on the current generated `AgentMessageEvt` wire DTO, so the adapter preserves all currently generated assistant fields and leaves usage unset.

## Review

Approved (2026-06-30). Independently re-ran: **app tests 608 passed (up from 600
— the agent's 8 new replay tests)**; `flutter analyze` clean except the known-unrelated
`axisAlignment` deprecation at `lib/ui/chat/widgets/input_bar.dart:802`. Commit
`0e8aa04` scoped to app only (session_history_replay.dart +148 + sync_service +
transcript_event + tests); collision guard held (pi-ext agent was disjoint).

Adapter verified: pure data/sync→domain adapter (0 Hive/UI/ViewModel imports —
ports/adapters discipline). Determinism: eventIds are
`server:<session_id>:<history-type>:<stable-key>:<ts>`, deliberately ignore the
outer `SessionHistory.inReplyTo` request id; duplicate identical server facts produce
identical event ids for store dedupe; `UserInputEvt` → `UserMessageConfirmed` with
`clientMessageId` set to the wire event id (confirms by client id). 8 tests cover
user/image, assistant, tool request/result, compaction, request-id-independence,
duplicate-id stability, unsupported-event fail-fast, missing-session-id fail-fast.
