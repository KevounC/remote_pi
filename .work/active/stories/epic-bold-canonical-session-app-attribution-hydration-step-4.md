---
id: epic-bold-canonical-session-app-attribution-hydration-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-canonical-session-app-attribution-hydration
depends_on: [epic-bold-canonical-session-app-attribution-hydration-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
