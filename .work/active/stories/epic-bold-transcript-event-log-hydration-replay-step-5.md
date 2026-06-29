---
id: epic-bold-transcript-event-log-hydration-replay-step-5
kind: story
stage: implementing
tags: [refactor, bold, app, pi-extension, cockpit]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-hydration-replay-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Add replay regression fixtures and remove replacement assumptions

**Priority**: Medium  
**Risk**: Low  
**Source Lens**: testing integrity / dead weight  
**Files**: `app/test/data/sync/sync_service_test.dart`, `app/test/domain/transcript/`, `pi-extension/src/extension.test.ts`, `cockpit/test/`, `.orchestration/contracts/` or equivalent fixture location

## Current State

```text
Tests prove identical SessionHistory causes no Hive churn, but the accepted
history batch is still treated as the desired active message box. Comments in
pi-extension still say the app substitutes its cache wholesale.
```

## Target State

```json
{
  "name": "reconnect-history-is-replay-not-replace",
  "session_id": "sess-replay-fixture",
  "local_events": [
    { "kind": "user_submitted", "eventId": "local:cli_1", "clientMessageId": "cli_1", "text": "still visible" }
  ],
  "server_replay": [
    { "type": "user_input", "ts": 10, "id": "srv_1", "text": "authoritative older row" }
  ],
  "assertions": [
    "server replay appends deterministic events",
    "local event remains visible",
    "duplicate replay appends zero events",
    "foreign session is ignored before projection",
    "truncated or empty replay does not delete local log"
  ]
}
```

## Implementation Notes

- Add regression tests from the contract outward: deterministic replay adapter, store append/dedupe, projection after replay, and visible message rows.
- Cover lifecycle convergence from `.agents/rules/testing-integrity.md`: success, error, abort/cancel, compaction, reconnect replay, shutdown/session replacement, and session switch filtering.
- Replace code comments that describe `session_history` as substitution with comments that describe append/dedupe replay.
- If shared fixtures are too heavy before generated-protocol lands, mirror the same fixture content in app/pi-extension/cockpit tests and mark it as future generated-contract coverage.

## Acceptance Criteria

- [ ] A regression proves replay does not delete local events absent from the server batch.
- [ ] A regression proves duplicate replay is idempotent at the event store and projection cache.
- [ ] A regression proves empty/truncated replay is non-destructive.
- [ ] A regression proves foreign-session replay is ignored before touching event log, projection rows, streaming, or working state.
- [ ] Replacement-oriented comments/tests are removed or rewritten to the replay model.
- [ ] Verification commands for app, pi-extension, and Cockpit targeted tests are recorded in story implementation notes.

## Rollback

Remove the new replay fixtures/tests only if the replay implementation is rolled back. Do not weaken existing session-sync, pending-send, or compaction tests.
