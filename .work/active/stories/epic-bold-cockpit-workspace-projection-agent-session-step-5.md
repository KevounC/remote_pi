---
id: epic-bold-cockpit-workspace-projection-agent-session-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-agent-session
depends_on: [epic-bold-cockpit-workspace-projection-agent-session-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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

- [ ] UI widgets read `session.projection`, `projection.turn`, and immutable projected transcript entries instead of branching on `AgentStatus.streaming`, `_turnStartedAt`, or mutable tool entries.
- [ ] `AgentStatus.streaming` and `AgentSnapshot.isStreaming` are removed or documented as a short-lived wire compatibility adapter with no UI consumers.
- [ ] Stop/cancel affordance, controls enabled state, elapsed timer, tab activity indicator, edit-dialog status label, transcript tool card, and notification count preserve current visible behavior.
- [ ] Tests cover the high-risk UI projection paths listed in the implementation notes.
- [ ] `flutter test` targeted cockpit tests, `flutter analyze`, and `dart format .` pass, or skipped commands/tooling blockers are recorded.

## Risk

Medium. This is mostly consumer migration, but it removes compatibility fields after several refactors. The risk is UI drift: a busy agent might look idle, controls may enable too early, or a tool card may stop updating.

## Rollback

Restore legacy getters and UI branches (`AgentStatus.streaming`, `isStreaming`, `turnStartedAt`, mutable `ToolEntry`) while keeping the projection code side-by-side. If tests reveal projection drift, fix the projection before re-removing compatibility state.
