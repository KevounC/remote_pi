---
id: epic-bold-transcript-event-log-store-step-4
kind: story
stage: review
tags: [refactor, bold, app, pi-extension]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Re-key transcript retention by canonical session and keep projections disposable

**Priority**: Medium  
**Risk**: High  
**Source Lens**: naming inconsistency / persistence key consolidation  
**Files**: `app/lib/data/local/boxes.dart`, `app/lib/data/local/records/session_index_record.dart`, `app/lib/data/repositories/session_read_repository.dart`, `app/lib/data/repositories/home_read_repository.dart`, `app/lib/data/sync/sync_service.dart`, `pi-extension/src/session/remote_session.ts`

## Current State

```dart
static String msgsBoxName(String epk, String roomId) =>
    'msgs_${toAppEpk(epk)}__$roomId';
static String sessionKey(String epk, String roomId) => '$epk:$roomId';
```

## Target State

```dart
final class TranscriptSessionKey {
  final String peerId;
  final String roomId;
  final String sessionId;
  String get durableKey => '$peerId:$roomId:$sessionId';
}

// Event truth:
transcript_events_<peer>__<room>__<session>

// Rebuildable projection cache:
msgs_<peer>__<room>__<session>

// Room reachability/runtime remains room-scoped:
runtime key = '$peerId:$roomId'
```

## Implementation Notes

- Use the canonical-session `session_id` for event and message-projection boxes. If canonical-session step 5 is not fully landed, isolate the fallback in `_activeTranscriptKeyOrNull` and name it as compatibility-only.
- `sessions_index` may need session-scoped durable transcript rows while `runtime` stays `(peer, room)` because reachability is relay-room state, not transcript identity.
- Old peer+room projection boxes and old session-index rows are abandoned/ignored, not deleted. Re-sync/replay repopulates the new event box and derived projection for the active session.
- Read repositories should open projection boxes through the same `TranscriptSessionKey` or an explicit compatibility overload; avoid spreading loose triples.
- Keep the event store append-only. Projection caches may be diffed, cleared, or rebuilt from the event log.

## Acceptance Criteria

- [x] Two `session_id`s on the same `(peer, room)` do not share transcript events or projected rows.
- [x] Runtime reachability/working room snapshots remain keyed by `(peer, room)` unless the canonical-session feature explicitly changes them.
- [x] Old peer+room boxes are preserved for rollback and not destructively migrated.
- [x] Read repositories document whether they consume session-scoped keys or temporary compatibility keys.
- [x] Targeted app persistence tests pass.

## Implementation

- Re-key strategy: transcript truth uses `TranscriptSessionKey(peerId, roomId, sessionId)` and disposable message projections use `RemoteSessionRef(peerEpk, roomId, sessionId)`, so both `transcript_events_<peer>__<room>__<session>` and `msgs_<peer>__<room>__<session>` are scoped by canonical SDK `session_id`.
- Rollback preservation: legacy peer+room boxes/rows are ignored rather than deleted; `SessionIndexRecord.tryFromJson` drops old rows missing `session_id`, while old Hive files remain available for rollback.
- Runtime scope: runtime reachability/working snapshots continue to use `LocalBoxes.runtimeKey(epk, roomId)` because relay-room liveness is not transcript identity.
- Repository documentation: `SessionReadRepository`, `HomeReadRepository`, and `SessionIndexRecord` now document session-scoped reads versus room-scoped runtime/compatibility rows; `SyncService._activeTranscriptKeyOrNull` quarantines the temporary no-session state instead of falling back to peer+room transcript persistence.
- Pi-extension touch: `remoteSessionDurableKey` documents the shared canonical durable key shape alongside `RemoteSessionIssuer`.
- Verification:
  - Targeted app persistence tests: 65 passed (`flutter test test/data/local/transcript_event_store_hive_test.dart test/data/repositories/read_repository_test.dart test/data/sync/sync_service_test.dart`).
  - Full app test: 597 passed.
  - App analyze: 1 pre-existing info (`axisAlignment` deprecated in `lib/ui/chat/widgets/input_bar.dart:802`); command exits non-zero on that info per current Flutter analyzer behavior.
  - Pi-extension typecheck: clean (`tsc --noEmit`; only expected pnpm/npmrc warnings).

## Rollback

Switch read/write paths back to peer+room keys. Because old projection boxes were preserved, rollback restores the previous cache behavior; event boxes can remain orphaned until cleanup.
