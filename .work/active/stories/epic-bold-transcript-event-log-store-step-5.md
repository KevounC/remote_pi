---
id: epic-bold-transcript-event-log-store-step-5
kind: story
stage: done
tags: [refactor, bold, app, pi-extension]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] App event-store and sync tests prove event log is append-only/deduped and projections are rebuildable.
- [x] Pi-extension tests prove session history derives from the event log and preserves current wire behavior.
- [x] Convergence tests cover false/idle after success, error, cancel/abort, compaction, reconnect, and session replacement.
- [x] Verification commands are recorded in each story's implementation notes.

## Implementation

- Files changed: `app/test/data/local/transcript_event_store_hive_test.dart`, `app/test/data/sync/sync_service_test.dart`, `pi-extension/src/extension.test.ts`.
- App event-store coverage: added a mirrored store/replay fixture proving duplicate append is ignored, append order is stable, canonical session boxes isolate foreign `session_id`s, replay-derived projection rebuilds rows, and late confirmation suppresses an earlier timeout failure.
- App sync coverage: added regressions proving the transcript log drives replay after deleting `msgs`, duplicate replay has no churn, success/error/cancel/compaction converge idle, and session replacement partitions event logs/projections across canonical session ids.
- Pi-extension coverage: added a mirrored transcript-event fixture proving `session_sync` projects from `TranscriptEventLog`, ignores foreign-session events, preserves current `session_history` wire shape, and records the future generated-contract migration note inline.
- Verification:
  - `cd app && PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter test test/data/local/transcript_event_store_hive_test.dart test/data/sync/sync_service_test.dart` — 64 passed, 0 failed.
  - `cd app && PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter test` — 600 passed, 0 failed.
  - `cd pi-extension && export PNPM_HOME=~/projects/remote_pi/.pnpm-store npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache && corepack pnpm typecheck` — passed (`tsc --noEmit`).
  - `cd pi-extension && export PNPM_HOME=~/projects/remote_pi/.pnpm-store npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache && corepack pnpm exec vitest run src/extension.test.ts` — 157 passed, 4 failed; failures matched the documented false-alarm discriminator, not transcript/session-sync regressions: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, `a second same-name agent joins as <name>#2 instead of being refused`.
- Discrepancies from design: no shared `.orchestration/contracts/` fixture was added; the same fixture is mirrored in app/pi-extension tests with an inline generated-contract migration note because generated protocol contracts have not landed.
- Adjacent issues parked: none.

## Rollback

Remove the new tests/fixtures only if the event-store implementation is also rolled back. Do not weaken existing row/session-sync tests to make the refactor pass.

## Review

Approved (2026-06-30). Independently re-ran: **app tests 600 passed (up from 597 —
the agent's new store/replay + sync regressions)**; pi-ext `corepack pnpm typecheck`
clean; **full pi-ext suite 666 passed | 3 skipped | 0 failed (44 files)** — fully green
(up from 665 — the agent's new mirrored transcript-event fixture). Commit `1b26423`
scoped to app + pi-ext only; collision guard held.

Regression coverage verified: app event-store (append idempotence, stable order,
canonical-session isolation, projection rebuild, late-confirmation-over-timeout);
app sync (replay after msgs deletion, duplicate-replay no-churn, idle convergence on
success/error/cancel/compaction, session-replacement partitioning); pi-ext
(`session_sync` projects from `TranscriptEventLog`, ignores foreign-session events,
preserves `session_history` wire shape). **transcript-event-log-store arc complete (5/5).**
