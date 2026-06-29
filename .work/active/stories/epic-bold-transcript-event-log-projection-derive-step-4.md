---
id: epic-bold-transcript-event-log-projection-derive-step-4
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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
