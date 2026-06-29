---
id: epic-bold-transcript-event-log-store-step-1
kind: story
stage: review
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

## Implementation notes
- Files changed: `app/lib/domain/contracts/transcript_event_store.dart`, `app/lib/data/local/records/transcript_event_record.dart`, `app/lib/data/local/transcript_event_store_hive.dart`, `app/lib/data/local/boxes.dart`, `app/lib/config/dependencies.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/domain/contracts/contracts.dart`.
- Tests added: none in this step; the adapter is side-by-side and not yet used by sync projection logic.
- Verification: attempted `dart format ... && flutter analyze` from `app/`, but Flutter/Dart failed before analysis because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp` / `engine.realm`). `flutter test` was skipped for the same toolchain write failure.
- Discrepancies from design: `SyncService` receives the port as an optional named dependency so existing tests/constructors remain source-compatible until later projection steps consume the event store.
- Adjacent issues parked: none.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blocker**: `app/lib/config/dependencies.dart:64` registers `TranscriptEventStore` with `_injector.addRepository<TranscriptEventStore>(...)`, but `TranscriptEventStore` does not extend/implement the `Repository` marker required by `CustomInjector.addRepository<T extends Repository>`. A direct analyzer run against the changed app files with writable `HOME` reported:

```text
error - lib/config/dependencies.dart:64:27 - 'TranscriptEventStore' doesn't conform to the bound 'Repository' of the type parameter 'T'. Try using a type that is or is a subclass of 'Repository'. - type_argument_not_matching_bounds
```

Fix by either making the store port/adapter conform to the repository lifecycle contract (including `dispose()` if registered as a repository) or registering it via the appropriate injector path for non-Repository singletons (for example `addOther`) while preserving DI access for `SyncService`.

**Verification**: Implementation commit `cd7f85e` inspected. `flutter analyze && flutter test` from `app/` could not start because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp` / `engine.realm`). A narrower direct analyzer command was run with `HOME=/tmp/pi-dart-home` and found the blocker above before tests could be meaningfully run. Append-only adapter semantics looked structurally correct (event-id key dedupe, monotonic `seq`, per-session box key, sessionId mismatch guard), but the app currently does not analyze with this DI registration.

## Implementation notes (bounce re-fix)
- Files changed: `app/lib/config/dependencies.dart`.
- Tests added: none; this is a DI registration correction.
- Discrepancies from design: registered `TranscriptEventStore` through `addOther` instead of making the port implement `Repository`; this preserves the store as a persistence port without imposing a fake `dispose()` lifecycle contract.
- Adjacent issues parked: none.
- Verification: pending full app verification in this run after the dependent app stories are integrated.
