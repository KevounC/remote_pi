---
id: epic-bold-transcript-event-log-store-step-3
kind: story
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Replace pi-extension `_messageBuffer` with `TranscriptEventLog`

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / single source of truth  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/transcript_event.ts`, `pi-extension/src/session/transcript_event_log.ts`, `pi-extension/src/session/transcript_projection.ts`, `pi-extension/src/extension.test.ts`

## Current State

```ts
type BufferMsg = { role: "user" | "assistant" | "toolResult" | string; content?: unknown; timestamp?: number };
let _messageBuffer: BufferMsg[] = [];

pi.on("message_end", (event) => {
  const m = event?.message;
  if (m.role === "user" || m.role === "assistant" || m.role === "toolResult") {
    _messageBuffer.push(m as BufferMsg);
  }
});

const allEvents = _mapAgentMessagesToEvents(_messageBuffer);
```

## Target State

```ts
export class TranscriptEventLog {
  private readonly events: TranscriptEvent[] = [];
  private readonly seen = new Set<string>();

  append(event: TranscriptEvent): boolean {
    if (this.seen.has(event.eventId)) return false;
    this.seen.add(event.eventId);
    this.events.push(event);
    return true;
  }

  forSession(sessionId: string): readonly TranscriptEvent[] {
    return this.events.filter((event) => event.sessionId === sessionId);
  }
}

const _transcriptLog = new TranscriptEventLog();
pi.on("message_end", (event) => {
  for (const transcriptEvent of sdkMessageToTranscriptEvents(event.message, _currentRemoteSessionId())) {
    _transcriptLog.append(transcriptEvent);
  }
});
```

## Implementation Notes

- Do not add extension disk persistence in this slice. The old `_messageBuffer` was process-local; the new log is process-local but typed, session-scoped, append-only, and deduped.
- Convert user, assistant text/tool blocks, tool results, compaction markers, provider errors, and `agent_done` into `TranscriptEvent`s at their boundary hooks.
- Build outgoing `session_history` from a projection of `_transcriptLog.forSession(sessionId)`, preserving the existing wire shape until generated-protocol/canonical-session changes land.
- Export test seams mirroring `_setMessageBufferForTest` only as event-log seams (`_setTranscriptEventsForTest`, `_getTranscriptEventsForTest`) to retire buffer-shaped tests.
- `session_new`/session replacement resets or rotates by session id; relay stop/start/reconnect preserves the active session log.

## Acceptance Criteria

- [ ] `_messageBuffer` is removed or reduced to a temporary SDK-message adapter with no projection responsibility.
- [ ] `session_sync` output, limit/truncation, image replay, compaction replay, tool result stringification, and late-attach sync are preserved.
- [ ] Reconnect preserves the transcript event log for the same session; session replacement does not replay old events into the new session id.
- [ ] `corepack pnpm test -- extension.test.ts` and `corepack pnpm typecheck` pass or blockers are recorded.

## Rollback

Restore `_messageBuffer` and `_mapAgentMessagesToEvents` as the `session_history` source. The app Hive event store can remain unused while extension rollback is applied.
