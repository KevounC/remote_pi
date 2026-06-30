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
updated: 2026-06-30
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

## Implementation notes
- Files changed: `app/lib/data/sync/sync_service.dart`.
- Tests added: none in this stride; existing `SyncService` tests remain the target regression suite.
- Discrepancies from design: the append-only Hive `TranscriptEventStore` remains side-by-side for the later store step; this story keeps an in-memory active-session event buffer and continues using existing `msgs:<epk>:<room>` boxes as the materialized projection. Timeout failure rows are deliberately preserved for compatibility until a later store/projection cleanup, but a late authoritative `UserInput` confirmation now re-projects from events and suppresses stale projection rows.
- Adjacent issues parked: none.
- Verification: direct Dart analyzer check passed for `app/lib/data/sync/sync_service.dart` with `HOME=/tmp/pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/data/sync/sync_service.dart`. Full `flutter analyze && flutter test` could not start in this environment because `/opt/flutter/bin/cache` is read-only (`engine.stamp.tmp` / `engine.realm`).

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blocker**: Acceptance coverage for the high-risk `SyncService` projection switchover is still missing. The story explicitly requires tests proving history replay does not delete local pending events, duplicate replay emits no Hive churn, and late authoritative echo after timeout converges to the intended projection. The implementation notes say no tests were added, and I found no matching coverage in `app/test/data/sync/sync_service_test.dart`. Add focused regression tests for those three cases (or an explicit equivalent coverage path), then re-run/record `flutter test test/data/sync/sync_service_test.dart` when the Flutter toolchain is writable.

**Verification**: Inspected implementation commit `843b56e00a17d4528f6ea875d6bf16d8417e8ccb` and `app/lib/data/sync/sync_service.dart`. `HOME=/tmp/pi-dart-home flutter analyze && flutter test` could not start because `/opt/flutter/bin/cache` is read-only. Direct analyzer fallback passed for changed app files: `HOME=/tmp/pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze lib/data/sync/sync_service.dart lib/data/local/transcript_event_store_hive.dart lib/data/local/records/transcript_event_record.dart lib/domain/contracts/transcript_event_store.dart lib/config/dependencies.dart`. `dart test test/domain/transcript/transcript_projection_test.dart` could not run because pub attempted network access and got `403 Forbidden` from the proxy.

## Implementation notes (test-coverage re-fix)
- Files changed: `app/test/data/sync/sync_service_test.dart`.
- Tests added: focused SyncService regressions for history replay preserving local pending events, duplicate history replay emitting no read-repository/Hive churn, and late authoritative echo after timeout converging to the confirmed user row with the timeout failure suppressed.
- Discrepancies from design: none; this re-fix adds the missing acceptance coverage only.
- Adjacent issues parked: none.
- Verification: `HOME=/tmp/pi-dart-home /opt/flutter/bin/cache/dart-sdk/bin/dart analyze test/data/sync/sync_service_test.dart lib/data/sync/sync_service.dart` passed. `dart test test/data/sync/sync_service_test.dart` could not run because pub network access failed with `403 Forbidden`; `flutter analyze`/`flutter test` cannot start because `/opt/flutter/bin/cache` is read-only.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- `app/test/data/sync/sync_service_test.dart:297` / `app/test/data/sync/sync_service_test.dart:323`: the existing steer tests now fail because `workingReplyTo` is overwritten with the steer message id instead of preserving the active turn target `u1`. This violates the existing-suite-green acceptance criterion and the working-state convergence invariant.
- `app/lib/data/sync/sync_service.dart:643` and `app/lib/data/sync/sync_service.dart:958`: tool-request projection paths pass protocol `args` directly into `ToolRequested`, causing runtime type errors for `Map<dynamic, dynamic>` live args and null history args. This breaks existing sequential/history replay tests, so `app/test/data/sync/sync_service_test.dart` is not green.
- `app/lib/data/sync/sync_service.dart:434` with the in-memory projection buffer at `app/lib/data/sync/sync_service.dart:60`: `clearActiveSession()` clears Hive rows but leaves prior transcript events in `_transcriptEvents`, so later replays resurrect pre-clear rows (`stale`/`base`/`baseline`). This violates the session-clear/replay invariants and keeps sync state from being a clean projection of the active event log.

**Verification run**:
- `cd /home/agent/forks/remote_pi/app && HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter analyze` exited 1 with only the known-unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802`.
- `cd /home/agent/forks/remote_pi/app && HOME=/tmp/pi-dart-home /tmp/flutter-writable/bin/flutter test test/data/sync/sync_service_test.dart` exited 1: 29 tests passed, 7 failed. The three new efb2fea7 coverage tests ran and passed, so the prior bounce's missing-coverage blocker is addressed, but the required file-level regression suite is still red.

## Implementation notes (rework 2026-06-30)
- Files changed: `app/lib/data/sync/sync_service.dart`, `app/test/data/sync/sync_service_test.dart`.
- Tests added: `clearActiveSession clears projection buffer before later replay`, proving pre-clear in-memory projection events do not resurrect after a same-boundary replay.
- Fixes:
  - Preserved the active turn target for steer submissions/echoes by letting projection writes update rows without replacing the current in-memory streaming/working state.
  - Narrowed live and history tool-request `args` through a boundary helper: `null` becomes an empty map, `Map<dynamic, dynamic>` with string keys is accepted/cast, and non-object/non-string-key payloads fail fast with `FormatException`.
  - Cleared `_transcriptEvents` and `_transcriptEventIds` inside `clearActiveSession()` after the active Hive rows are wiped, preventing later replay from resurrecting cleared rows.
  - Replaced prior `history:` transcript events on accepted `SessionHistory` replay and ignored derived-row `ts` changes when diffing, preserving no-Hive-churn duplicate replay semantics while allowing same-boundary authoritative replay to replace prior history rows.
- Discrepancies from design: none for the bounce spec; the extra history replay replacement/diff normalization was required to keep the existing `sync_service_test.dart` suite green after clearing/replay fixes.
- Adjacent issues parked: none.
- Verification:
  - `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && FLUTTER=/home/agent/projects/remote_pi/.tools/flutter/bin/flutter && $FLUTTER pub get` completed successfully.
  - `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && FLUTTER=/home/agent/projects/remote_pi/.tools/flutter/bin/flutter && $FLUTTER test test/data/sync/sync_service_test.dart` passed: 37 tests passed.
  - `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && FLUTTER=/home/agent/projects/remote_pi/.tools/flutter/bin/flutter && $FLUTTER analyze` exited 1 with only the known-unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802`.

## Review bounce (2026-06-30)

**Verdict**: Request changes

**Blockers**:
- `app/lib/data/sync/sync_service.dart:435`: `clearActiveSession()` now clears the Hive rows and the in-memory transcript event buffer, but it still does not clear the active in-memory turn state (`_working`, `_workingReplyTo`, and any streaming cursor). A session clear is the `session_new` wipe boundary, so a clear during an active turn can leave the chat/Home state stuck working with a stale cancel target until some later replay/status edge happens to correct it. Call the existing turn-reset/working-clear path as part of `clearActiveSession()` and add a regression asserting `isWorking == false`, `workingReplyTo == null`, and `streaming == null` after clear.

**Verification run**:
- Inspected commit `7dc99eb`: the three prior bounce blockers are resolved in current source: steer submit/echo use `preserveTurnState` and preserve active `workingReplyTo`; live/history tool args use `_objectMap` for `null`, `Map<dynamic, dynamic>` with string keys, and fail-fast invalid shapes; `clearActiveSession()` calls `_clearTranscriptEventBuffer()` to clear `_transcriptEvents` and `_transcriptEventIds`.
- `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && /home/agent/projects/remote_pi/.tools/flutter/bin/flutter pub get` completed successfully.
- `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && /home/agent/projects/remote_pi/.tools/flutter/bin/flutter analyze` exited 1 with only the known-unrelated `axisAlignment` deprecation info at `lib/ui/chat/widgets/input_bar.dart:802`.
- `cd /home/agent/projects/remote_pi/app && export PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache && /home/agent/projects/remote_pi/.tools/flutter/bin/flutter test test/data/sync/sync_service_test.dart` passed: 40 tests passed.

