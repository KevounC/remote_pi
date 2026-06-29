---
id: epic-bold-transcript-event-log-projection-derive-step-6
kind: story
stage: implementing
tags: [refactor, bold, pi-extension, app, cockpit]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-5]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
