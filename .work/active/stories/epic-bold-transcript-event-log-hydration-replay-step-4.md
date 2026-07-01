---
id: epic-bold-transcript-event-log-hydration-replay-step-4
kind: story
stage: done
tags: [refactor, bold, cockpit]
parent: epic-bold-transcript-event-log-hydration-replay
depends_on: [epic-bold-transcript-event-log-hydration-replay-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] Cockpit `get_messages` and live `_onEvent` append to the same local transcript event log or reducer seam.
- [x] Duplicate `get_messages` hydration is idempotent and does not duplicate entries.
- [x] Tool call/result hydration produces one projected tool entry without mutating a persisted domain object after publish.
- [x] Session/path switch filters old events out of the active projection.
- [x] Targeted Cockpit mapper/projection tests pass, or `flutter test` blockers are recorded.

## Implementation

- Added a Cockpit transcript event log seam that accepts both live RPC transcript events and `get_messages` hydration events, deduping by event id before projection.
- `AgentSession` now keeps transcript truth in the local event log and rebuilds the UI `_entries` list from `deriveCockpitTranscript(_transcriptLog.forSession(activeSessionIdOrLocalPath))`; `_entries` remains only derived display state.
- Duplicate `get_messages` hydration is idempotent for the active projection, including tool call/result rows, because replayed event ids are appended only once.
- Session/path switches now filter projection input by `sessionId`, so older local/live events remain in the log but are excluded from the active session projection.
- Tool hydration continues to produce immutable projected `ProjectedToolMessage` values; completion replaces the projected value rather than mutating a published domain object.
- Verification from `cockpit/` with `PUB_CACHE=~/projects/remote_pi/.pub-cache` and `~/projects/remote_pi/.tools/flutter/bin/flutter`:
  - `flutter pub get --offline` passed.
  - `flutter analyze` passed: No issues found.
  - `flutter test` passed: 230 tests passed.

## Rollback

Restore direct `TranscriptMessage` mapping and `_entries` population. App/pi-extension replay semantics remain unaffected.

## Review

Approved (2026-06-30). Independently re-ran: **cockpit tests 230 passed (up from 228
— the agent's new transcript-projection tests)**; `flutter analyze` clean. Commit
`0ddc86b` scoped to cockpit only (transcript_event + agent_session + rpc_data_mapper
+ test); collision guard held.

Hydration seam verified: `CockpitTranscriptEventLog` accepts both live RPC transcript
events AND `get_messages` hydration events, deduping by event id before projection.
`AgentSession` keeps transcript truth in the local event log; `_entries` is derived
display state rebuilt from `deriveCockpitTranscript(_transcriptLog.forSession(...))`.
Duplicate `get_messages` hydration idempotent (replayed event ids appended once,
including tool call/result rows). Session/path switch filters projection by `sessionId`
(older events stay in log, excluded from active projection). Tool hydration produces
immutable `ProjectedToolMessage` (completion replaces, doesn't mutate published object).
