---
id: epic-bold-transcript-event-log-store-step-3
kind: story
stage: review
tags: [refactor, bold, pi-extension]
parent: epic-bold-transcript-event-log-store
depends_on: [epic-bold-transcript-event-log-store-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] `_messageBuffer` is removed or reduced to a temporary SDK-message adapter with no projection responsibility.
- [x] `session_sync` output, limit/truncation, image replay, compaction replay, tool result stringification, and late-attach sync are preserved.
- [x] Reconnect preserves the transcript event log for the same session; session replacement does not replay old events into the new session id.
- [x] `corepack pnpm test -- extension.test.ts` and `corepack pnpm typecheck` pass or blockers are recorded.

## Implementation

- Replaced projection-owned transcript storage with `TranscriptEventLog`, a process-local typed append-only log with event-id dedupe and session-scoped reads; `_messageBuffer` remains only as a legacy SDK-message test/compatibility adapter that populates transcript events.
- Preserved `session_sync` wire shape and projection behavior for limit/truncation, image replay, compaction replay, tool result stringification, late-attach sync, reconnect preservation, and session-replacement reset.
- Captured provider-error and `agent_done` boundaries as transcript events without projecting new public `session_history` wire variants.
- Added coverage for direct transcript-event seam dedupe plus active-session scoping so old-session events do not replay into the current session.
- Verification:
  - `corepack pnpm typecheck` passed.
  - `corepack pnpm build` passed.
  - Full `corepack pnpm exec vitest run src/extension.test.ts`: 156 passed, 4 failed, 0 skipped in this file. The failures match the known false-alarm discriminator: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, `a second same-name agent joins as <name>#2 instead of being refused`.
  - Targeted transcript/session-sync run `corepack pnpm exec vitest run src/extension.test.ts -t "session_sync|cumulative transcript event log|successful reconnect preserves session_id"`: 12 passed, 148 skipped.

## Rollback

Restore `_messageBuffer` and `_mapAgentMessagesToEvents` as the `session_history` source. The app Hive event store can remain unused while extension rollback is applied.
