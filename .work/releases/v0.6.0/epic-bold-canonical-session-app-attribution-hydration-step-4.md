---
id: epic-bold-canonical-session-app-attribution-hydration-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-canonical-session-app-attribution-hydration
depends_on: [epic-bold-canonical-session-app-attribution-hydration-step-3]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 4: Hydrate by replaying session history through the transcript event seam

## Current State
```dart
Future<void> _applyHistory(SessionHistory h) async {
  final rows = _convertHistory(h.events);
  final desired = <MessageRecord>[
    for (var i = 0; i < rows.length; i++) rows[i].copyWith(seq: i),
    for (var j = 0; j < preserved.length; j++)
      preserved[j].copyWith(seq: rows.length + j),
  ];
  for (final k in box.keys.toList()) {
    if ((k as num).toInt() >= desired.length) {
      await box.delete(k);
    }
  }
  for (var i = 0; i < desired.length; i++) {
    await box.put(i, desired[i].toJson());
  }
}
```

The current implementation diffs instead of clearing, which fixed flicker, but it is still a replacement reducer: the active box is reconciled to the latest `session_history` payload. That is not the long-term replay model and remains dangerous if a foreign history passes attribution.

## Target State
```dart
Future<void> _applyHistory(SessionHistory h) async {
  final ref = _activeSessionRef();
  if (ref == null) return;

  for (final event in historyToTranscriptEvents(h, sessionId: ref.sessionId)) {
    _appendTranscriptEvent(event);
  }

  final projection = deriveTranscriptProjection(
    sessionId: ref.sessionId,
    events: _transcriptEvents,
  );
  await _writeProjectionDiff(ref, projection);
}
```

## Implementation Notes
- Step 1 guarantees `_applyHistory` only receives same-session history. Keep a defensive session check here anyway so direct tests and future call sites cannot bypass the boundary.
- Convert `SessionHistory.events` to `TranscriptEvent`s with deterministic event ids and append/dedupe them. Reconnect replay is additive/idempotent; it must not delete rows simply because a replay omitted them.
- Use the existing `app/lib/domain/transcript/transcript_event.dart` and `transcript_projection.dart` seam when available. If the transcript projection implementation is still partial, keep the compatibility conversion in `SyncService` but structure it as append/dedupe + projection diff, not replacement-to-history.
- Preserve local pending `UserMessageSubmitted` events that have not been confirmed by server replay. Late authoritative confirmation wins over send-timeout failure according to the transcript-event-log sibling design.
- Keep `session_started_at` as ordering/high-water metadata inside the same `session_id`; it is not an identity substitute and must not allow a mismatched session through.

## Acceptance Criteria
- [ ] Same-session reconnect history replays idempotently: no duplicate rows, no box churn for identical replay, no dropped local pending message.
- [ ] A replay missing older local rows does not delete them solely because they are absent from the payload.
- [ ] Foreign or missing-session history is already dropped by Step 1 and has a focused regression test proving the active session box/index remain unchanged.
- [ ] Tests cover optimistic pending + authoritative echo, duplicate replay, late confirm after timeout, tool request/result collapse, compaction replay, and `working` converging false after replayed done/error/cancel paths available in the event model.
- [ ] `flutter test test/data/sync/sync_service_test.dart` and transcript projection tests pass.

## Risk
High. This changes the app's hydration reducer. The step should be a single, isolated implementation commit so rollback can restore the current `_convertHistory`/diff path without reverting session gating or storage attribution.

## Rollback
Revert `_applyHistory` to the current diff-to-desired implementation while keeping Step 1's session gate. If rollback is necessary, document that hydration is temporarily same-session replacement rather than replay.

## Implementation
- Reducer approach: `_applyHistory` now fail-closes on direct `session_id` mismatch, seeds the in-memory transcript seam from existing active-box rows for compatibility, appends deterministic `historyToTranscriptEvents(...)`, and writes the derived projection diff. History events are no longer removed/replaced on replay.
- Idempotency guarantee: duplicate history event ids are deduped before projection; identical replay produces no additional Hive writes, while partial same-session replay preserves older local rows and local pending submissions.
- Test coverage: focused direct `_applyHistory` foreign-session bypass regression; same-session duplicate replay/no-churn; replay missing older rows; pending + authoritative echo; late confirm after timeout; tool request/result collapse; compaction replay; and working/streaming convergence false after terminal live and replay paths available in the current event model.
- Deferred scope: `SessionHistoryEvent` currently has no explicit done/error/cancel history variants; replay convergence is covered through `AgentMessageEvt` and `CompactionEvt`, while live done/error/cancel convergence remains covered by sync tests.

## Review

Approved (2026-06-30) with deeper verification — HIGH-risk hydration reducer.
Independently re-ran: `flutter test test/data/sync/sync_service_test.dart` →
55/55; `flutter test test/domain/transcript/` → 11/11. `flutter analyze` clean
in owned files (only known `axisAlignment` info).

Read the reducer directly and confirmed each load-bearing invariant:
- **Foreign-session drop**: `if (h.sessionId != ref.sessionId) return;` defensive
  check present (defends direct/bypassed call sites, not just upstream gating).
- **Idempotency / no box churn**: `_appendTranscriptEvents` dedupes by
  `event.eventId` via `_transcriptEventIds.add(...)`; on duplicate `changed`
  stays false → no `_writeProjectionDiff` → identical replay produces zero Hive
  writes. Genuinely implemented, not just tested.
- **Pending preservation**: `_seedExistingTranscriptEvents` re-reads the box and
  preserves `pending` user rows as `UserMessageSubmitted` (late authoritative
  confirm wins).
- **Omitted-rows preservation**: additive append/dedupe never deletes rows absent
  from a replay payload.
- **High-water mark**: `sessionStartedAt` compared as ordering metadata, not
  identity — stale replays rejected.

Test coverage directly maps to every acceptance criterion (foreign bypass,
idempotent identical replay/no-churn, omitted older rows, pending+echo, late
confirm, compaction replay, convergence). Commit `4d294c4` scoped to owned
app files; no collision with parallel Wave-5 bundles (correctly left others'
unstaged). Deferred scope (no explicit done/error/cancel `SessionHistoryEvent`
variants) is a legitimate event-model limitation, clearly recorded.
