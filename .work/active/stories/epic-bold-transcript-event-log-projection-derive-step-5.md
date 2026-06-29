---
id: epic-bold-transcript-event-log-projection-derive-step-5
kind: story
stage: implementing
tags: [refactor, bold, cockpit]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Make Cockpit transcript entries immutable projection outputs

**Priority**: Medium
**Risk**: Medium
**Source Lens**: code smell / naming inconsistency
**Files**: `cockpit/lib/app/cockpit/domain/entities/transcript_message.dart`, `cockpit/lib/app/cockpit/domain/entities/transcript_event.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`

## Current State

```dart
final class TmTool extends TranscriptMessage {
  TmTool({required this.callId, required this.name, required this.args});
  bool done = false;
  bool isError = false;
  String resultText = '';
}

// AgentSession._populateTranscript clears _entries and maps Tm* directly.
```

Cockpit's `get_messages` mapper and live `_onEvent` fold are independent reducers.

## Target State

```dart
sealed class CockpitTranscriptEvent { /* same kind names as TranscriptEvent */ }

final class ProjectedToolMessage extends ProjectedTranscriptMessage {
  const ProjectedToolMessage({required this.callId, required this.name, required this.args, required this.status, this.resultText = ''});
  final ToolProjectionStatus status;
}

final projection = deriveCockpitTranscript(events);
_entries
  ..clear()
  ..addAll(projection.entries.map(toAgentEntry));
```

## Implementation Notes

- Cockpit remains local-only; do not add relay, pairing, mobile session routing, or crypto.
- Retire mutable `TmTool` as the domain model. Local reducer internals may mutate while building immutable projection output, but published domain entities should be value objects.
- `_onEvent` should append local transcript events and re-project open text/tool buffers instead of owning a parallel fold unrelated to `get_messages`.
- Keep session-path naming separate from remote `session_id`; if canonical-session has landed, store it as optional opaque metadata only.

## Acceptance Criteria

- [ ] `rpc_data_mapper.transcriptMessages` and live `_onEvent` use the same projection rules for user/text/thinking/tool messages.
- [ ] Tool start/result cannot leave a mutable domain object half-updated after projection.
- [ ] Existing Cockpit transcript tests pass; add focused mapper/projection tests if coverage is absent.
- [ ] Targeted cockpit `flutter test` passes or platform/tooling blockers are recorded.

## Risk

Medium. Cockpit uses process/RPC lifecycle; a projection rewrite must not break local session switching or live streaming display.

## Rollback

Restore `TmTool` mutation and direct `_entries` folding. App/pi-extension event projection remains unaffected.
