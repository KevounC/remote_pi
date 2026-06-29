---
id: epic-bold-transcript-event-log-hydration-replay-step-1
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-store]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
