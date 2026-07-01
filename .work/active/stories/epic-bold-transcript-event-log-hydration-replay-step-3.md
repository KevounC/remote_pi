---
id: epic-bold-transcript-event-log-hydration-replay-step-3
kind: story
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-hydration-replay-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation

- `session_history` remains built by `SdkSessionProjection.buildSessionHistoryMessage()` from the session-scoped `TranscriptEventLog` via `projectSessionHistory()`, with legacy SDK-message fixtures adapted into transcript events only at the test seam.
- Replaced replacement-oriented comments around `session_new` with replay-compatible wording: session rotation plus transcript-log reset is the correctness boundary; the empty broadcast is only an attached-owner compatibility notification.
- Added coverage that identical transcript facts replay stable `session_history.events` across different `session_sync` request ids, and strengthened reconnect coverage to compare pre- and post-reconnect event payloads.
- Verification:
  - `corepack pnpm typecheck` passed.
  - `corepack pnpm build` passed.
  - `corepack pnpm exec vitest run src/extension.test.ts` reported 162 passed / 4 failed / 0 skipped in this file. The 4 failures match the documented false-alarm discriminator: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, and `a second same-name agent joins as <name>#2 instead of being refused`.
  - Targeted replay checks passed: 4 passed / 162 skipped for `successful reconnect preserves session_id, sessionStartedAt, and transcript history`, `event-log seam dedupes by eventId and session_sync scopes to active session`, `session_sync replays stable history events across request ids`, and `session_sync projects the transcript event log fixture across canonical-session boundary`.

## Review

Approved (2026-06-30). Independently re-ran (clean state): `corepack pnpm typecheck`
clean; **full pi-ext suite 671 passed | 3 skipped | 0 failed (44 files)** — fully green
(up from 670 — the agent's new stable-history-event + reconnect-payload tests). The 4
failures the agent reported are genuinely the false-alarm signature — confirmed by clean
orchestrator re-run (0 failures). The agent CORRECTLY classified them.

Replay-compatibility verified (2× consistent): `session_history` built by
`SdkSessionProjection.buildSessionHistoryMessage()` from session-scoped
`TranscriptEventLog` via `projectSessionHistory()` (not mutable projection rows or
app-replacement assumptions). Identical transcript facts replay stable
`session_history.events` across different `session_sync` request ids. Session rotation
+ transcript-log reset is the correctness boundary (empty broadcast is only an
attached-owner compatibility notification, not a destructive delete). 20
session_history/replay tests pass. Commit `c0751a2` scoped to pi-ext only
(extension.test.ts +67 + index.ts); collision guard held.
