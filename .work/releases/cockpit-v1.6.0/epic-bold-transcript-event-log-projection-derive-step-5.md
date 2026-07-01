---
id: epic-bold-transcript-event-log-projection-derive-step-5
kind: story
stage: done
tags: [refactor, bold, cockpit]
parent: epic-bold-transcript-event-log-projection-derive
depends_on: [epic-bold-transcript-event-log-projection-derive-step-4]
release_binding: cockpit-v1.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] `rpc_data_mapper.transcriptMessages` and live `_onEvent` use the same projection rules for user/text/thinking/tool messages.
- [x] Tool start/result cannot leave a mutable domain object half-updated after projection.
- [x] Existing Cockpit transcript tests pass; add focused mapper/projection tests if coverage is absent.
- [x] Targeted cockpit `flutter test` passes or platform/tooling blockers are recorded.

## Implementation

- Added `deriveCockpitTranscript` as the shared event-to-projected-message reducer for history and live RPC transcript events.
- Replaced mutable `TmTool` domain output with immutable `ProjectedToolMessage` value objects carrying `ToolProjectionStatus`; tool args are copied into unmodifiable maps.
- Reworked `RpcDataMapper.transcriptMessages` to translate `get_messages` wire history into `CockpitTranscriptEvent`s, then derive projected transcript entries with the same rules used live.
- Reworked `AgentSession._onEvent` transcript handling to append local transcript events and re-project user/text/thinking/tool entries instead of maintaining separate `_openText`/`_openThinking`/`_openTools` reducers; non-transcript info/notice/UI-request entries remain UI-local.
- Kept `sessionPath` as the restored session-file path; `get_messages` `session_id` is used only as opaque metadata for mapper event IDs.
- Added `test/data/rpc_data_mapper_transcript_projection_test.dart` with 3 focused projection/mapper tests.
- Verification: `flutter pub get --offline`, `flutter analyze`, targeted `flutter test test/data/rpc_data_mapper_transcript_projection_test.dart`, and full `flutter test` all passed.
- Collision: none. Did not edit `cockpit_viewmodel.dart`, `workspace_projection.dart`, `pane_item.dart`, or `workspace_projection_test.dart`.

## Risk

Medium. Cockpit uses process/RPC lifecycle; a projection rewrite must not break local session switching or live streaming display.

## Rollback

Restore `TmTool` mutation and direct `_entries` folding. App/pi-extension event projection remains unaffected.

## Review

Approved (2026-06-30). Independently re-ran `flutter test
test/data/rpc_data_mapper_transcript_projection_test.dart` → 3/3; whole-cockpit
`flutter analyze` 0 issues. Commit `aaafa59` (agent self-amended `f5993ad`→
`aaafa59`; diff is 4 lines in the story .md only — code intact) scoped to owned
files; collision guard held — did NOT touch cockpit_viewmodel.dart/
workspace_projection.dart/pane_item.dart (owned by parallel
workspace-document-step-6). Shared projection reducer (history + live) and
immutable ProjectedToolMessage value objects verified; `session_id` used only
as opaque mapper metadata, session-path naming kept separate as required.
