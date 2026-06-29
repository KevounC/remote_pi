---
id: epic-bold-transcript-event-log-hydration-replay-step-4
kind: story
stage: implementing
tags: [refactor, bold, cockpit]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-hydration-replay-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Convert Cockpit `get_messages` hydration to event replay projection

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: pattern drift / missing abstraction  
**Files**: `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/domain/entities/transcript_event.dart`, `cockpit/lib/app/cockpit/domain/entities/transcript_message.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/test/`

## Current State

```dart
// cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart
List<TranscriptMessage> transcriptMessages(Object? data) {
  // Maps get_messages {messages:[AgentMessage]} directly to mutable
  // TranscriptMessage rows; TmTool is later completed by mutation.
}

// AgentSession._populateTranscript clears _entries and loads mapped rows.
```

## Target State

```dart
final events = getMessagesToTranscriptEvents(
  data,
  sessionId: activeSessionIdOrLocalPath,
);
_transcriptLog.appendAll(events);
final projection = deriveCockpitTranscriptProjection(
  sessionId: activeSessionIdOrLocalPath,
  events: _transcriptLog.forSession(activeSessionIdOrLocalPath),
);
_entries
  ..clear()
  ..addAll(projection.entries.map(toAgentEntry));
```

## Implementation Notes

- This keeps Cockpit local-only. It does not add relay pairing, mobile routing, or remote session authority.
- `get_messages` is a server/Pi snapshot source like `session_history`; convert it to deterministic events and dedupe by event id before projecting.
- Clearing `_entries` is acceptable only as clearing a derived UI list immediately before repopulating from the event log; it must not clear transcript truth.
- Retire `TmTool` mutation as the hydration truth. A local reducer can mutate while deriving immutable projection output, but published domain messages should be value objects.
- Use the same event kind names as app/pi-extension to keep generated-protocol/patchbay migration straightforward.

## Acceptance Criteria

- [ ] Cockpit `get_messages` and live `_onEvent` append to the same local transcript event log or reducer seam.
- [ ] Duplicate `get_messages` hydration is idempotent and does not duplicate entries.
- [ ] Tool call/result hydration produces one projected tool entry without mutating a persisted domain object after publish.
- [ ] Session/path switch filters old events out of the active projection.
- [ ] Targeted Cockpit mapper/projection tests pass, or `flutter test` blockers are recorded.

## Rollback

Restore direct `TranscriptMessage` mapping and `_entries` population. App/pi-extension replay semantics remain unaffected.
