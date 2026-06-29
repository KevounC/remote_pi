---
id: epic-bold-transcript-event-log-hydration-replay-step-3
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-hydration-replay-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Make pi-extension `session_history` replay-compatible and independent of app replacement

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / boundary clarity  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/transcript_event_log.ts`, `pi-extension/src/session/transcript_projection.ts`, `pi-extension/src/protocol/types.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
function _buildSessionHistoryMessage(inReplyTo: string, limit: number | undefined) {
  // Mirror semantics: always return the last N events. App SUBSTITUTES its
  // local cache with this response — no delta/since_ts logic.
  const allEvents = _mapAgentMessagesToEvents(_messageBuffer);
  return { type: 'session_history', in_reply_to: inReplyTo, events: slice, eos: true, truncated };
}

function _resetSessionForNew(inReplyTo: string): void {
  _messageBuffer = [];
  _broadcastToActive({ type: 'session_history', in_reply_to: inReplyTo, events: [] });
}
```

## Target State

```ts
function _buildSessionHistoryMessage(
  inReplyTo: string,
  limit: number | undefined,
): Extract<ServerMessage, { type: 'session_history' }> {
  const sessionId = _remoteSessionIssuer.current();
  const projection = projectSessionHistory({
    sessionId,
    events: _transcriptLog.forSession(sessionId),
    limit: Math.min(limit ?? _getSyncLimit(), _getSyncLimit()),
  });
  return {
    type: 'session_history',
    in_reply_to: inReplyTo,
    session_started_at: _sessionStartedAt ?? 0,
    events: projection.events,
    eos: true,
    truncated: projection.truncated,
  };
}
```

## Implementation Notes

- Remove comments and tests that rely on the app substituting its cache wholesale; `session_history` is a replay payload.
- Build history from the store sibling's `TranscriptEventLog` / projection adapter when present. If `_messageBuffer` is still in a legacy seam, its only job is to feed transcript events; it must not own replay semantics.
- Keep outgoing wire shape stable until generated-protocol/canonical-session changes land.
- `_resetSessionForNew` rotates/resets the extension event log for the new session and may broadcast an empty history as a compatibility notification, but correctness must not depend on app-side destructive replacement.
- Ensure per-request `session_sync` still goes only to the requesting owner; broadcast remains only for global new-session compatibility.

## Acceptance Criteria

- [ ] `session_history` output is derived from session-scoped `TranscriptEvent`s, not from mutable projection rows or app replacement assumptions.
- [ ] Identical server facts produce stable history events across reconnects and different `session_sync` request ids.
- [ ] Empty history on new session does not have to delete old app rows; session rotation/event-log reset provides the boundary.
- [ ] Existing limit/truncated, image replay, compaction replay, tool result stringification, and late-attach sync tests remain green.
- [ ] `corepack pnpm test -- extension.test.ts` and `corepack pnpm typecheck` pass or blockers are recorded.

## Rollback

Restore `_messageBuffer` / `_mapAgentMessagesToEvents` as the direct `session_history` source and the old replacement-oriented comments/tests. App replay work remains local.
