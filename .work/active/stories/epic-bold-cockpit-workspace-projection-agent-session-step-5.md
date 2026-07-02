---
id: epic-bold-cockpit-workspace-projection-agent-session-step-5
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-agent-session
depends_on: [epic-bold-cockpit-workspace-projection-agent-session-step-4]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 5: Migrate UI consumers to the AgentSession projection and retire compatibility state

## Current State

```dart
// cockpit/lib/app/cockpit/ui/widgets/agent_composer.dart
if (session.isStreaming) {
  session.stop();
  return;
}
final streaming = session.isStreaming;
final controlsEnabled = session.isAlive && !streaming;
...
final active = widget.session.isStreaming && widget.session.turnStartedAt != null;
```

```dart
// cockpit/lib/app/cockpit/ui/widgets/pane_view.dart
final isEmpty = agent?.status == AgentStatus.empty;
final streaming = agent?.isStreaming ?? false;
```

```dart
// cockpit/lib/app/cockpit/ui/widgets/agent_transcript.dart
ToolEntry() => _ToolCard(tool: entry as ToolEntry),
```

## Target State

```dart
final projection = session.projection;
if (projection.turn.canStop) {
  session.stop();
  return;
}
final controlsEnabled = projection.isAlive && !projection.turn.working;
final elapsedStart = projection.turn.startedAt;
```

```dart
final projection = agent?.projection;
final isEmpty = projection?.lifecycle == AgentProcessLifecycle.empty;
final activeTurn = projection?.turn.working ?? false;
```

```dart
// Transcript widget renders immutable projected entries.
ProjectedToolMessage(:final status) => _ToolCard(status: status, ...),
```

## Implementation Notes

- Migrate `agent_composer.dart`, `pane_view.dart`, `agent_transcript.dart`, `agent_edit_dialog.dart`, and `CockpitViewModel.notificationCount` to read `AgentSessionProjection` / `AgentTurnProjection` directly.
- Retain legacy getters only while a file still needs them; remove `AgentStatus.streaming` and mutable `ToolEntry` / `TmTool` state after all consumers move.
- Preserve user-visible labels for now (`streaming` may still display in edit dialog if that was the old label), but source it from `AgentTurnProjection` so the name is display compatibility, not domain truth.
- Add focused widget/domain tests rather than broad golden churn: stop button when working, controls disabled while working/pending, elapsed timer starts/stops, tab activity indicator, tool card done/error rendering, and notification badge after turn end.
- Do not introduce relay/mobile concepts into Cockpit UI. The projection is local process + transcript + workspace state only.

## Acceptance Criteria

- [x] UI widgets read `session.projection`, `projection.turn`, and immutable projected transcript entries instead of branching on `AgentStatus.streaming`, `_turnStartedAt`, or mutable tool entries.
- [x] `AgentStatus.streaming` and `AgentSnapshot.isStreaming` are removed or documented as a short-lived wire compatibility adapter with no UI consumers.
- [x] Stop/cancel affordance, controls enabled state, elapsed timer, tab activity indicator, edit-dialog status label, transcript tool card, and notification count preserve current visible behavior.
- [x] Tests cover the high-risk UI projection paths listed in the implementation notes.
- [x] `flutter test` targeted cockpit tests, `flutter analyze`, and `dart format .` pass, or skipped commands/tooling blockers are recorded.

## Implementation

- Migrated `agent_composer.dart`, `pane_view.dart`, `agent_edit_dialog.dart`, and `CockpitViewModel.notificationCount` to source busy/alive/lifecycle/model/context state from `session.projection`, `projection.turn`, and `projection.controls`.
- Migrated `agent_transcript.dart` to render immutable `ProjectedTranscriptMessage` values directly, including `ProjectedToolMessage` done/error states, while leaving only non-projected side-channel rows (`InfoEntry`, `WorkedEntry`, `NoticeEntry`, `UiRequestEntry`) in `AgentEntry`.
- Removed `AgentSession.isStreaming`, `AgentSession.turnStartedAt`, `AgentSnapshot.isStreaming`, and the mutable transcript compatibility entries (`UserEntry`, `AssistantTextEntry`, `ThinkingEntry`, `ToolEntry`). `RpcDataMapper` retains only the documented short-lived wire adapter from legacy `isStreaming` payloads into `AgentTurnProjection`; no UI consumers read it.
- Preserved visible behavior for stop/cancel affordance, disabled controls while pending/working, elapsed timer start/stop, tab activity spinner, edit-dialog state label, projected tool card done/error rendering, and notification badge counts.
- Test coverage updated for projection-backed turn state, pending/busy controls semantics, elapsed convergence, projected transcript text/tool rows, notification count clearing, and added `test/ui/agent_transcript_projection_test.dart` for projected tool done/error rendering.
- Verification: `flutter pub get --offline` passed; `flutter analyze` passed; full `flutter test` passed (222 tests); targeted projection tests passed after final cleanup. Targeted owned-file `dart format --output=none --set-exit-if-changed ...` passed. The exact requested `dart format` check path falls back because `dart` is not on PATH in this sandbox; the SDK dart full-tree check also reports pre-existing formatting drift in six unowned cockpit files outside this story's write set, so those files were not modified.

## Risk

Medium. This is mostly consumer migration, but it removes compatibility fields after several refactors. The risk is UI drift: a busy agent might look idle, controls may enable too early, or a tool card may stop updating.

## Rollback

Restore legacy getters and UI branches (`AgentStatus.streaming`, `isStreaming`, `turnStartedAt`, mutable `ToolEntry`) while keeping the projection code side-by-side. If tests reveal projection drift, fix the projection before re-removing compatibility state.

## Review

Approved (2026-06-30). Independently re-ran: whole-cockpit `flutter analyze` →
No issues found; full `flutter test` → 222/222 (incl. new
agent_transcript_projection_test.dart). Commit `3c3698e` scoped to cockpit only
(UI widgets + agent_session + agent_entry + agent_snapshot + tests + story .md);
no cross-subproject collision.

Compat retirement verified directly: `AgentStatus` enum is now
`{empty, booting, idle, crashed}` (no `streaming` variant); `AgentSession.
isStreaming`/`turnStartedAt` + `AgentSnapshot.isStreaming` + mutable transcript
entries (`UserEntry`/`AssistantTextEntry`/`ThinkingEntry`/`ToolEntry`) removed;
`RpcDataMapper` retains only the documented short-lived wire adapter from legacy
`isStreaming` → `AgentTurnProjection` (no UI consumers). UI widgets now read
`session.projection`/`projection.turn`/`projection.controls` directly. Visible
behavior preserved across all 7 paths (stop/cancel, disabled-while-working
controls, elapsed timer start/stop, tab activity spinner, edit-dialog label,
projected tool card done/error, notification badge count/clear). The 6-file
pre-existing dart format drift is unowned (outside this story's write set) —
correctly left unmodified.
