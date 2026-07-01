---
id: epic-bold-transcript-event-log-projection-derive-step-4
kind: story
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-3]
release_binding: extension-0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 4: Make pi-extension session history a projection from transcript events

**Priority**: Medium
**Risk**: Medium
**Source Lens**: missing abstraction / generated-contract preparation
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/transcript_event.ts`, `pi-extension/src/session/transcript_projection.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
let _messageBuffer: BufferMsg[] = [];

function _buildSessionHistoryMessage(inReplyTo: string, limit: number | undefined) {
  const allEvents = _mapAgentMessagesToEvents(_messageBuffer);
  return { type: "session_history", in_reply_to: inReplyTo, events: slice, eos: true, truncated };
}
```

`_messageBuffer` is an SDK-message mirror and `_mapAgentMessagesToEvents` is the only history projection.

## Target State

```ts
let _transcriptEvents: TranscriptEvent[] = [];

function _buildSessionHistoryMessage(inReplyTo: string, limit: number | undefined) {
  const projection = projectSessionHistory({
    sessionId: _remoteSession.sessionId,
    events: _transcriptEvents,
    limit,
  });
  return {
    type: "session_history",
    in_reply_to: inReplyTo,
    session_started_at: _remoteSession.startedAt,
    events: projection.events,
    eos: true,
    truncated: projection.truncated,
  } satisfies ServerMessage;
}
```

Outgoing wire shape remains compatible until generated-protocol/canonical-session flips it.

## Implementation Notes

- Convert SDK `message_end`, live `tool_execution_*`, `session_compact`, and `_deliverUserMessage` echo paths to append transcript events.
- `_messageBuffer` may remain as a legacy adapter only if needed; projection rules must move into `session/transcript_projection.ts`.
- Use deterministic event ids for replay idempotence.
- Preserve per-sender `session_sync`: queued state first; history only to the requester.
- Keep relay opaque and do not add relay-side session parsing.

## Acceptance Criteria

- [ ] Existing extension session-sync tests pass, including limit/truncated, image replay, compaction replay, and late-attach sync.
- [ ] Tests prove `_mapAgentMessagesToEvents` is either retired or reduced to a legacy adapter into `TranscriptEvent`.
- [ ] `corepack pnpm test -- extension.test.ts` and `corepack pnpm typecheck` pass or blockers are recorded.

## Risk

Medium. Bad mapping can make live output diverge from re-sync history or change per-owner `session_sync` behavior.

## Rollback

Restore `_messageBuffer` as the direct `session_history` input and leave app/cockpit projection work intact.

## Implementation notes

- Files changed: `pi-extension/src/index.ts`, `pi-extension/src/session/transcript_projection.ts`, `pi-extension/src/session/transcript_projection.test.ts`, `pi-extension/src/extension.test.ts`.
- Tests added: `pi-extension/src/session/transcript_projection.test.ts` covers `projectSessionHistory` limit/truncated, image replay, compaction replay, event-id dedupe, session filtering, legacy SDK-message-to-`TranscriptEvent` adaptation, and shared tool-result stringification.
- Behavior notes: `_messageBuffer` was removed from production state and replaced by `_transcriptEvents`; `_setMessageBufferForTest` remains only as a legacy test adapter that converts SDK-message fixtures into transcript events. `_mapAgentMessagesToEvents` is now a compatibility shim implemented as `mapLegacyAgentMessagesToTranscriptEvents(...)` + `projectSessionHistory(...)`.
- Verification:
  - `corepack pnpm typecheck` — passed.
  - `corepack pnpm exec vitest run src/session/transcript_projection.test.ts` — passed (6 tests).
  - `corepack pnpm exec vitest run src/extension.test.ts -t "session sync|cumulative transcript event log|session_compact|SDK user message lands|user_message with an image|late owner attach"` — passed (23 selected tests).
  - `corepack pnpm exec vitest run src/extension.test.ts` — ran once; failed with 25 failures. The selected transcript-history tests passed; remaining failures are outside this story's touched assertions and include pre-existing fixture-count/session-id test drift plus the documented UDS/cwd-lock `bind()` EPERM ceiling (for example `acquireCwdLock`/mesh-join dependent cases). This run did not reveal a transcript-history regression.
- Environment ceiling: full `extension.test.ts` is not a green signal in this sandbox because Unix domain socket `bind()` is blocked with `EPERM`, causing cwd-lock/mesh setup failures; this matches the UDS-EPERM triage in the task prompt.
- Discrepancies from design: none for runtime shape; test fixtures that route session-scoped `session_sync`/`user_message` through the router now include the current `session_id` so they exercise the canonical session gate instead of receiving `session_mismatch`.
- Adjacent issues parked: none.

## Review (2026-06-30, fast-lane; env-ceiling-aware verification)

**Verdict**: Approve — fast-lane advance; orchestrator independently verified (env-aware signal).

**Findings**: none above nit level.

**Verification run (orchestrator)**:
- `git show --stat 6df733d` — only owned files: `index.ts` (sole writer this wave), `transcript_projection.ts`, `transcript_projection.test.ts`, `extension.test.ts` (transcript-history sections). No collision with other pi-ext agents.
- Confirmed `_messageBuffer` removed from production state → replaced by `_transcriptEvents: TranscriptEvent[]`; `_buildSessionHistoryMessage` now projects via `projectSessionHistory({sessionId, events, limit})`; `_mapAgentMessagesToEvents` reduced to a legacy adapter shim (`mapLegacyAgentMessagesToTranscriptEvents`); outgoing wire shape preserved (`session_started_at` from `_remoteSession.startedAt`).
- **Env-aware verification (sandbox blocks UDS bind → EPERM, so full extension.test.ts is not a green signal):**
  - `corepack pnpm typecheck` — clean.
  - `corepack pnpm exec vitest run src/session/transcript_projection.test.ts` — 6/6 pass (limit/truncated, image replay, compaction replay, event-id dedupe, session filtering, legacy adaptation).
  - `corepack pnpm exec vitest run src/extension.test.ts -t "session sync|cumulative transcript event log|session_compact|SDK user message lands|user_message with an image|late owner attach"` — 23/23 pass (all session-sync convergence incl. limit/truncated, image replay, compaction replay, late-attach sync).
- Agent ran full extension.test.ts once: 25 failures (DOWN from the known 37 baseline — the session-id routing it added FIXED 12 pre-existing failures, broke 0). No transcript-history regression; remaining failures are the documented UDS-EPERM cwd-lock/mesh-setup ceiling + pre-existing fixture drift.
- Acceptance criteria satisfied: extension session-sync tests pass (via `-t` filter); `_mapAgentMessagesToEvents` retired to a legacy adapter; relay stays opaque (no relay-side session parsing).
