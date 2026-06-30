---
id: epic-bold-cockpit-workspace-projection-agent-session-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-agent-session
depends_on: [epic-bold-cockpit-workspace-projection-agent-session-step-3, epic-bold-cockpit-workspace-projection-workspace-document-step-6]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Realize AgentSession from WorkspaceDocument tab descriptors

## Current State

```dart
// cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart
AgentSession _buildAgent(
  String id,
  Project project,
  String cwd, {
  String? title,
  bool autoStartRelay = false,
  String? restoreSessionPath,
  String? preferredModelId,
  ThinkingLevel preferredThinking = ThinkingLevel.off,
}) {
  final s = AgentSession(...)
    ..preferredModelId = preferredModelId
    ..preferredThinking = preferredThinking;
  s.onTurnEnd = () => _onAgentTurnEnd(s);
  s.onPreferenceChanged = () => _scheduleSave(project.id);
  _sessions[s.id] = s;
  unawaited(_bootAgent(s, cwd, project, restoreSessionPath));
  return s;
}
```

```dart
Map<String, dynamic> _sessionToJson(PaneItem s, Project project) {
  final a = s as AgentSession;
  if (a.status == AgentStatus.empty) {
    return <String, dynamic>{'type': 'empty', 'title': a.title};
  }
  return <String, dynamic>{
    'type': 'agent',
    'sub': _subOf(a.workingDirectory, project.path),
    'title': a.title,
    if (a.sessionPath != null) 'sessionPath': a.sessionPath,
    if (a.autoStartRelay) 'auto_start_relay': true,
    if (a.preferredModelId != null) 'preferred_model': a.preferredModelId,
    if (a.preferredThinking != ThinkingLevel.off) 'preferred_thinking': a.preferredThinking.name,
  };
}
```

## Target State

```dart
// WorkspaceProjection consumes WorkspaceTab descriptors and owns live AgentSession realization.
Future<bool> realizeAgent(WorkspaceTab tab, Project project) async {
  final cwd = tab.relativeSubpath.isEmpty
      ? project.path
      : '${project.path}/${tab.relativeSubpath}';
  final session = AgentSession.fromWorkspaceTab(
    tab: tab,
    projectId: project.id,
    workingDirectory: cwd,
    factory: _rpcFactory,
  );
  session.onTurnEnd = () => _events.add(WorkspaceProjectionEvent.agentTurnEnded(session.id));
  session.onProjectionChanged = () => _events.add(WorkspaceProjectionEvent.tabDescriptorChanged(session.id));
  _items[tab.id] = session;
  await session.boot(restoreSessionPath: tab.sessionPath, environment: _directConfig(session, project));
  return true;
}

WorkspaceTab descriptorForAgent(AgentSession session, Project project) =>
  WorkspaceTab.agent(
    id: session.id,
    relativeSubpath: _subOf(session.workingDirectory, project.path),
    title: session.title,
    sessionPath: session.projection.sessionPath,
    autoStartRelay: session.autoStartRelay,
    preferredModelId: session.projection.controls.preferredModelId,
    preferredThinking: session.projection.controls.preferredThinking,
  );
```

## Implementation Notes

- Consume the workspace-document feature's `WorkspaceTab` and `WorkspaceProjection` rather than keeping agent descriptor serialization in `CockpitViewModel`.
- `AgentSession` should be constructible from an agent `WorkspaceTab` descriptor and should expose a descriptor/projection snapshot for saving. The document remains the source of tab identity, title, subpath, session path, relay preference, and preferred model/thinking.
- Keep process/environment concerns in the projection adapter: `REMOTE_PI_DIRECT_CONFIG`, session baseline capture, and `SessionHistory` lookup are adapter effects, not domain document logic.
- Replace `onPreferenceChanged` with a projection/document update event where practical, so model/thinking/sessionPath/name changes update the document descriptor and save through the workspace command path.
- Preserve current `v: 1` layout JSON keys via the workspace document codec; this step should not change persisted layout shape.

## Acceptance Criteria

- [ ] Agent tabs are realized from `WorkspaceTab.agent` descriptors produced by the workspace document codec.
- [ ] `CockpitViewModel` no longer owns agent descriptor serialization directly; it asks the workspace projection for a `WorkspaceTab` descriptor or projection event.
- [ ] `sessionPath`, title/name-assigned changes, `autoStartRelay`, preferred model, and preferred thinking update the workspace document descriptor and still save debounced as before.
- [ ] Empty placeholder agent tabs remain distinguishable from booted agent tabs without relying on a process-lifecycle status named `empty` as persisted state.
- [ ] Layout JSON round-trip remains compatible with existing `v: 1` agent/empty descriptors.
- [ ] `flutter test` targeted workspace projection/layout tests and `flutter analyze` pass, or tooling blockers are recorded.

## Risk

Medium. This step crosses the workspace-document and agent-session seams. The primary risk is losing session-path or preference persistence while moving descriptor ownership out of `CockpitViewModel`.

## Rollback

Restore `_buildAgent`, `_restoreSession`, `_sessionToJson`, `onPreferenceChanged`, and direct `AgentSession` construction in `CockpitViewModel`. The earlier agent projection and transcript refactors can remain if their compatibility getters still satisfy the old serializer.

## Implementation

- Descriptor ownership moved into `WorkspaceProjection`: it now realizes agent tabs with `realizeAgent(WorkspaceTab.agent, Project)` and projects live agents back via `descriptorForAgent`, while `CockpitViewModel` delegates restore/serialization through the workspace projection.
- `AgentSession.fromWorkspaceTab` initializes tab identity, working directory, session path, relay preference, preferred model, and preferred thinking from the document descriptor; `workspaceDescriptor` snapshots the projection for saving.
- Replaced `onPreferenceChanged` with `onProjectionChanged` for session-path, title/name-assigned, preferred model, and preferred thinking updates; `setAutoStartRelay` also emits descriptor changes while `CockpitViewModel` keeps debounced layout saves.
- Empty placeholders now use an explicit `isPlaceholder` marker, so unbooted real agent tabs persist as `type: agent` instead of being inferred from lifecycle `AgentStatus.empty`.
- `v: 1` layout JSON shape is unchanged; existing round-trip tests still assert `agent` and `empty` descriptor keys.
- Tests: `flutter pub get --offline`; `flutter analyze` (0 issues); targeted `flutter test test/ui/workspace_projection_test.dart test/domain/workspace_document_codec_test.dart` (9/9); full `flutter test` (221/221).

## Review

Approved (2026-06-30). Independently re-ran: whole-cockpit `flutter analyze` →
No issues found; full `flutter test` → 221/221 (incl. 3 new layout/projection
tests). Commit `b920637` scoped to cockpit only (agent_session +
cockpit_viewmodel + workspace_projection + test + story .md); no cross-subproject
collision.

Descriptor ownership verified moved: `WorkspaceProjection` now owns
`realizeAgent`/`descriptorForAgent`/`AgentSession.fromWorkspaceTab`;
`CockpitViewModel` no longer has `_sessionToJson`/`_buildAgent` (delegates
through the projection). v:1 layout round-trip preserved
(`workspace_document_codec_test.dart` asserts `agent`/`empty` descriptor keys
unchanged). sessionPath/title/autoStartRelay/preferred-model/thinking update the
document descriptor + save debounced (via `onProjectionChanged`). Empty
placeholders now use explicit `isPlaceholder` (not `AgentStatus.empty` as
persisted state — meets the acceptance criterion). The `onProjectionChanged`
replacement of `onPreferenceChanged` is a clean simplification.
