---
id: epic-bold-transcript-event-log-store-step-5
kind: story
stage: implementing
tags: [refactor, bold, app, pi-extension]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Add cross-surface store/replay regression tests

**Priority**: Medium  
**Risk**: Low  
**Source Lens**: testing integrity / lifecycle convergence  
**Files**: `app/test/data/local/transcript_event_store_hive_test.dart`, `app/test/data/sync/sync_service_test.dart`, `pi-extension/src/extension.test.ts`, `.orchestration/contracts/` or equivalent fixture location

## Current State

```text
Existing tests prove row-granular message boxes and session_sync behavior, but
no test asserts that the append-only event log is the durable truth while
message rows are disposable projections.
```

## Target State

```json
{
  "session_id": "sess-store-fixture",
  "events": [
    { "kind": "user_submitted", "eventId": "local:cli_1", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "user_confirmed", "eventId": "server:cli_1", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "assistant_delta", "eventId": "server:chunk_1", "replyTo": "cli_1", "delta": "done" },
    { "kind": "assistant_done", "eventId": "server:done_1", "replyTo": "cli_1" }
  ],
  "assertions": [
    "duplicate append is ignored",
    "projection rows rebuild after deletion",
    "foreign session_id is ignored",
    "late confirmation suppresses timeout failure in projection"
  ]
}
```

## Implementation Notes

- Add app tests for append idempotence, stable order, per-session isolation, projection rebuild after deleting `msgs`, duplicate replay with no churn, and late authoritative confirmation after timeout.
- Add extension tests proving `_buildSessionHistoryMessage` reads from `TranscriptEventLog`, not `_messageBuffer`, while preserving existing wire output.
- Include convergence cases from `.agents/rules/testing-integrity.md`: success, error, abort/cancel, compaction, reconnect replay, shutdown/session replacement, and session switch filtering.
- If shared fixtures are too heavy before generated-protocol lands, mirror the same fixture content in app and extension tests and record the future generated-contract migration note in test comments.

## Acceptance Criteria

- [ ] App event-store and sync tests prove event log is append-only/deduped and projections are rebuildable.
- [ ] Pi-extension tests prove session history derives from the event log and preserves current wire behavior.
- [ ] Convergence tests cover false/idle after success, error, cancel/abort, compaction, reconnect, and session replacement.
- [ ] Verification commands are recorded in each story's implementation notes.

## Rollback

Remove the new tests/fixtures only if the event-store implementation is also rolled back. Do not weaken existing row/session-sync tests to make the refactor pass.
