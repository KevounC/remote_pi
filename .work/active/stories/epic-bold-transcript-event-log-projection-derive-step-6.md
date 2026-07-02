---
id: epic-bold-transcript-event-log-projection-derive-step-6
kind: story
stage: done
tags: [refactor, bold, pi-extension, app, cockpit]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-5]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 6: Add cross-surface projection fixtures and convergence checks

**Priority**: Medium
**Risk**: Low
**Source Lens**: testing integrity / generated-contract preparation
**Files**: `.orchestration/contracts/`, `app/test/domain/transcript/`, `pi-extension/src/extension.test.ts`, `cockpit/test/`

## Current State

```text
Each surface tests its own reducer shape. There is no shared fixture proving that
"optimistic send → echo → chunks → tool → done → replay" derives the same
messages in app, pi-extension history, and cockpit.
```

## Target State

```json
{
  "name": "optimistic-send-authoritative-replay",
  "session_id": "sess-fixture",
  "events": [
    { "kind": "user_submitted", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "user_confirmed", "clientMessageId": "cli_1", "text": "hello" },
    { "kind": "assistant_delta", "replyTo": "cli_1", "delta": "done" },
    { "kind": "assistant_done", "replyTo": "cli_1" }
  ],
  "projection": {
    "messages": [
      { "role": "user", "id": "cli_1", "status": "confirmed", "text": "hello" },
      { "role": "assistant", "replyTo": "cli_1", "text": "done" }
    ],
    "turn": { "status": "idle" }
  }
}
```

## Implementation Notes

- Use fixtures to pin projection semantics until generated-protocol replaces hand mirrors.
- Include negative/convergence cases: foreign `session_id` ignored, duplicate replay idempotent, failed send clears working, late confirm after timeout, cancel/error clears streaming, compaction produces a system row.
- Keep fixtures content-only and free of local paths/secrets.
- Document which fixture should become generated-protocol schema coverage later.

## Acceptance Criteria

- [ ] App, pi-extension, and cockpit tests consume at least one shared fixture or mirrored fixture with identical expected projection.
- [ ] Convergence tests cover `working` false after success, error, abort/cancel, compaction, reconnect replay, and session switch/filtering.
- [ ] Contract notes identify which fixture becomes generated-protocol schema coverage later.

## Risk

Low. Fixture churn is the main risk; it can be controlled by keeping fixtures small and behavior-focused.

## Rollback

Remove the new fixtures/tests. Runtime projection code from earlier steps remains in place.

## Implementation

- Fixtures added: `.orchestration/contracts/transcript_projection_fixtures.json` with `optimistic-send-authoritative-replay` and `convergence-negative-cases`. The fixture notes identify `optimistic-send-authoritative-replay` as the first candidate for generated-protocol schema coverage because it spans shared event kinds, required `session_id`, client-message correlation, streaming, tool, completion, and replay idempotence shape.
- Surfaces consuming fixtures this wave: app (`app/test/domain/transcript/transcript_projection_test.dart`) and cockpit (`cockpit/test/data/rpc_data_mapper_transcript_projection_test.dart`). Both read the shared fixture file and compare normalized projected messages/turn state against the fixture expectations.
- Pi-extension deferral: `pi-extension/src/extension.test.ts` fixture consumption was intentionally not implemented in this wave because `turn-state-machine-late-attach-step-3` owns pi-extension tests, and this wave was instructed not to edit `pi-extension/src/extension.test.ts` or `pi-extension/src/session/mesh_node.test.ts`.
- Convergence cases covered: app fixture tests cover foreign `session_id` filtering, duplicate replay idempotence, failed send clearing `working`, late confirm after timeout, assistant done clearing streaming after a cancellation-style failed send, compaction system row projection, reconnect-style replay, and idle turn convergence. Cockpit fixture tests cover the shared authoritative replay projection plus failed-send and assistant-done non-working convergence; cockpit currently has no projected system-row message type, so the compaction system-row expectation remains pinned by the app fixture and noted for generated-protocol/future cockpit schema coverage.
- Tests run: `~/projects/remote_pi/.tools/flutter/bin/flutter pub get` and `~/projects/remote_pi/.tools/flutter/bin/flutter test test/domain/transcript/` from `app/`; `~/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline` and `~/projects/remote_pi/.tools/flutter/bin/flutter test` from `cockpit/`.

## Review

Fast-lane approved (2026-06-30). Independently re-ran: app
`flutter test test/domain/transcript/` → 13/13 (incl. 2 new shared-fixture
convergence tests); cockpit `flutter test test/data/rpc_data_mapper_transcript_projection_test.dart`
→ 5/5 (#5's 3 original tests preserved + #6's 2 new shared-fixture tests — clean
merge, no clobbering). Commit `43c268d` scoped to a new shared fixture
(`transcript_projection_fixtures.json`, content-only — verified no secrets/paths)
+ app/cockpit test files + story .md; pi-ext deferral held (did NOT touch
extension.test.ts / mesh_node.test.ts, owned by the concurrent late-attach
agent). Acceptance criteria met: app + cockpit consume the shared fixture with
identical expected projection; convergence/negative cases (foreign session_id,
duplicate replay, failed-send clears working, late confirm, compaction system
row) covered.
