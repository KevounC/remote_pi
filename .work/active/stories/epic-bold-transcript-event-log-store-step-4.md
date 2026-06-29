---
id: epic-bold-transcript-event-log-store-step-4
kind: story
stage: implementing
tags: [refactor, bold, app, pi-extension]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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

- [ ] Two `session_id`s on the same `(peer, room)` do not share transcript events or projected rows.
- [ ] Runtime reachability/working room snapshots remain keyed by `(peer, room)` unless the canonical-session feature explicitly changes them.
- [ ] Old peer+room boxes are preserved for rollback and not destructively migrated.
- [ ] Read repositories document whether they consume session-scoped keys or temporary compatibility keys.
- [ ] Targeted app persistence tests pass.

## Rollback

Switch read/write paths back to peer+room keys. Because old projection boxes were preserved, rollback restores the previous cache behavior; event boxes can remain orphaned until cleanup.
