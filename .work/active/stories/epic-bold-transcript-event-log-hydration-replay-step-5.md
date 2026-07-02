---
id: epic-bold-transcript-event-log-hydration-replay-step-5
kind: story
stage: done
tags: [refactor, bold, app, pi-extension, cockpit]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-hydration-replay-step-4]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
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

## Implementation

- Added shared contract fixture `.orchestration/contracts/transcript_projection_fixtures.json` entry `reconnect-history-is-replay-not-replace`, carrying the story's local event/server replay/assertions plus app/cockpit projection expectations for future generated-contract coverage.
- App regression coverage:
  - `app/test/data/sync/sync_service_test.dart` now proves reconnect replay appends deterministic server events without deleting a local pending event, duplicate replay appends zero event-store entries and emits no projection-cache churn, empty/truncated replay is non-destructive, and foreign-session replay leaves the event log, rows, streaming, and working state untouched.
  - `app/test/domain/transcript/transcript_projection_test.dart` consumes the shared fixture and proves duplicate event ids and foreign-session events are ignored while local and replayed rows remain visible.
- Cockpit regression coverage: `cockpit/test/data/rpc_data_mapper_transcript_projection_test.dart` consumes the shared fixture and proves the local event-log/projection seam is additive, deduped, and session-scoped.
- Pi-extension regression coverage: `pi-extension/src/extension.test.ts` consumes the shared fixture and proves `session_sync` derives replay-compatible `session_history` from the transcript event log without replacement assumptions, deduping duplicate event ids and filtering foreign-session facts.
- Replacement-oriented comments/tests encountered in the touched replay surfaces now describe append/dedupe replay or compatibility fixture mirroring; no production code changes were required.
- Verification:
  - App targeted: `PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter test test/domain/transcript/transcript_projection_test.dart` passed: 14 tests passed.
  - App targeted: `PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter test test/data/sync/sync_service_test.dart` passed: 61 tests passed.
  - App full: `PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter test` passed: 612 tests passed.
  - Cockpit targeted: `PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter test test/data/rpc_data_mapper_transcript_projection_test.dart` passed: 10 tests passed.
  - Cockpit full: `PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline && PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter test` passed: 231 tests passed.
  - Pi-extension typecheck: `corepack pnpm typecheck` passed.
  - Pi-extension targeted replay test: `corepack pnpm exec vitest run src/extension.test.ts -t "reconnect replay contract"` passed: 1 passed, 166 skipped.
  - Pi-extension full targeted file: `corepack pnpm exec vitest run src/extension.test.ts` reported 163 passed / 4 failed in 167 tests. The failing test names match the documented false-alarm bucket, not replay integrity: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, and `a second same-name agent joins as <name>#2 instead of being refused`.

## Rollback

Remove the new replay fixtures/tests only if the replay implementation is rolled back. Do not weaken existing session-sync, pending-send, or compaction tests.

## Review

Approved (2026-06-30). Independently re-ran all three subprojects: **pi-ext 672
passed (up from 671)**; **app 612 passed (up from 610)**; **cockpit 231 passed (up
from 230)**; pi-ext typecheck clean. Commit `41dd808` scoped to app + pi-ext + cockpit
test files + shared contract fixture; collision guard held.

Regression coverage verified: shared contract fixture
`.orchestration/contracts/transcript_projection_fixtures.json` (entry
`reconnect-history-is-replay-not-replace`) consumed across all 3 subprojects. App
proves reconnect replay appends deterministic server events WITHOUT deleting local
pending events; duplicate replay idempotent by event/message id (no box churn);
empty/truncated replay non-destructive; foreign-session replay leaves log/rows/
streaming/working untouched. Cockpit proves the local event-log/projection seam is
additive, deduped, session-scoped. Pi-ext proves `session_sync` derives
replay-compatible `session_history` without replacement assumptions. **transcript-
event-log-hydration-replay arc complete (5/5).**
