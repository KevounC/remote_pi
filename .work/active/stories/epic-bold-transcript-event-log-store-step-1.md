---
id: epic-bold-transcript-event-log-store-step-1
kind: story
stage: implementing
tags: [refactor, bold, app]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-projection-derive]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Add the app Hive `TranscriptEvent` store adapter

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / ports and adapters  
**Files**: `app/lib/domain/contracts/transcript_event_store.dart`, `app/lib/data/local/records/transcript_event_record.dart`, `app/lib/data/local/transcript_event_store_hive.dart`, `app/lib/data/local/boxes.dart`, `app/lib/config/dependencies.dart`

## Current State

```dart
// app/lib/data/local/boxes.dart
//   DURABLE  msgs_<epk>__<roomId>   key = seq (int)        → MessageRecord
//   DURABLE  sessions_index         key = <epk>:<roomId>   → SessionIndexRecord
Future<Box<dynamic>> msgsBox(String epk, String roomId) =>
    Hive.openBox<dynamic>(msgsBoxName(epk, roomId));

static String msgsBoxName(String epk, String roomId) =>
    'msgs_${toAppEpk(epk)}__$roomId';
```

## Target State

```dart
abstract interface class TranscriptEventStore {
  Future<AppendTranscriptEventsResult> appendAll(
    TranscriptSessionKey key,
    Iterable<TranscriptEvent> events,
  );
  Future<List<TranscriptEvent>> readSession(TranscriptSessionKey key);
  Stream<List<TranscriptEvent>> watchSession(TranscriptSessionKey key);
}

final class TranscriptEventRecord {
  const TranscriptEventRecord({
    required this.eventId,
    required this.seq,
    required this.sessionId,
    required this.kind,
    required this.ts,
    required this.payload,
  });
  final String eventId;
  final int seq;
  final String sessionId;
  final String kind;
  final int ts;
  final Map<String, Object?> payload;
}

Future<Box<dynamic>> transcriptEventsBox(TranscriptSessionKey key) =>
    Hive.openBox<dynamic>(transcriptEventsBoxName(key));
```

## Implementation Notes

- Define the store port outside Hive. Domain/projection code depends on `TranscriptEventStore`, not on `LocalBoxes` or `Hive`.
- Store `eventId` as the Hive key and `seq` in the value. `appendAll` skips existing keys and appends only unseen events.
- `TranscriptEventRecord` is the only app-side JSON codec for the event algebra until generated-protocol replaces hand mirrors. Unknown `kind` fails fast at `fromJson`.
- Register `HiveTranscriptEventStore` in `config/dependencies.dart` so `SyncService` can receive the port through DI.
- Keep existing `msgs` and `sessions_index` APIs intact; they become projection storage in later steps.

## Acceptance Criteria

- [ ] App has a `TranscriptEventStore` port and a Hive adapter with no UI/network imports.
- [ ] Event boxes are keyed by `(peer, room, session_id)` and records require matching `sessionId`.
- [ ] Appending the same `eventId` twice is idempotent and preserves original seq/order.
- [ ] Existing `LocalBoxes.init` behavior still opens common boxes and wipes only `runtime`.
- [ ] Targeted store tests pass (`flutter test` or the nearest Dart/Hive test command available).

## Rollback

Remove the new store port/adapter/DI binding. Existing `msgs` boxes and `SyncService` direct row writes remain untouched.
