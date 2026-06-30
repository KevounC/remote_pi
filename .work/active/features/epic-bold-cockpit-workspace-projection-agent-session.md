---
id: epic-bold-cockpit-workspace-projection-agent-session
kind: feature
stage: done
tags: [refactor, bold, cockpit]
parent: epic-bold-cockpit-workspace-projection
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document, epic-bold-transcript-event-log]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Cockpit workspace — AgentSession as transcript projection

## Brief
`AgentSession` (`agent_session.dart`) fuses transcript renderer + RPC process
lifecycle + controls + relay state + turn machine (`AgentStatus` +
`_pendingSend` + `_awaitingUserEcho` + `_turnStartedAt` + `_openText` +
`_openTools`). It becomes a projection of the transcript event log (depends on
`epic-bold-transcript-event-log`) and the canonical turn state
(depends on `epic-bold-turn-state-machine`). Retires the fused
turn/streaming/tool fold (`_onEvent`, `agent_session.dart:436`).

## Epic context
- Parent epic: `epic-bold-cockpit-workspace-projection`
- Position: consumer of `workspace-document` + the transcript event log.

## Foundation references
- Evidence: `cockpit/lib/app/cockpit/ui/session/agent_session.dart:15-140`,
  `:316-380` (`_populateTranscript`), `:436-...` (`_onEvent` switch).

<!-- /agile-workflow:refactor-design pins the projection + process lifecycle. -->

## Design decisions

- Treat this as a behavior-preserving internal refactor. Cockpit remains local-only; no relay, pairing, mobile reconnect, or crypto behavior is introduced here.
- `AgentSession` becomes a projection of three inputs: the workspace document's agent `WorkspaceTab` descriptor, the transcript event log projection, and the turn-state projection. Process spawn/stdin/stdout remains an adapter around that projection.
- The transcript-event-log sibling owns the canonical transcript algebra. This feature consumes its Cockpit projection instead of re-inventing `TranscriptEvent` or a second tool/text fold.
- The turn-state-machine sibling owns `AgentTurnProjection` names (`status`, `turnId`, `replyTo`, `startedAt`). This feature coordinates with that shape and avoids adding a new Cockpit-only turn vocabulary that would block patchbay migration.
- Persisted workspace layout remains compatible with the current `v: 1` keys (`type`, `sub`, `title`, `sessionPath`, `auto_start_relay`, `preferred_model`, `preferred_thinking`). The workspace-document codec owns that JSON shape; agent-session only supplies descriptors.
- Dispatch rationale: direct-read only. The target was a bounded Cockpit module with explicitly named files plus landed sibling designs; no `.agents/skills/refactor-conventions/` or pattern catalog exists, and this sub-agent harness exposes no subagent tool despite the raised implementation tier. The scan covered code smells, missing abstractions, naming drift, and dead weight locally.
- Cycle-check note: `.work/bin/work-view --blocking` is required by the skill but the checkout's `.work/bin/` is empty (`.work/bin/work-view: No such file or directory`). I performed a manual cycle check before writing: the new stories did not previously exist, Step 1 depends outward on already-active prerequisite feature ids, Steps 2-5 chain forward only, and no existing item can point back to the new story ids before creation.

## Refactor Overview

`AgentSession` currently owns three different responsibilities in one `ChangeNotifier`:

- process lifecycle (`RpcGatewayFactory`, `_gateway`, `_sub`, `boot`, `killForRestart`, `dispose`);
- transcript reduction (`_entries`, `_openText`, `_openThinking`, `_openTools`, `_populateTranscript`, `_onEvent`);
- turn/UI state (`AgentStatus.streaming`, `_pendingSend`, `_turnStartedAt`, `isBusy`, `isStreaming`).

The target is a small projection surface:

```dart
final class AgentSessionProjection {
  const AgentSessionProjection({
    required this.tabId,
    required this.projectId,
    required this.title,
    required this.lifecycle,
    required this.turn,
    required this.transcript,
    required this.controls,
    this.relayStatus = RelayStatus.disconnected,
    this.sessionId,
    this.sessionPath,
    this.pendingLocalSend = false,
  });

  final String tabId;
  final String projectId;
  final String title;
  final String? sessionId;
  final AgentProcessLifecycle lifecycle;
  final AgentTurnProjection turn;
  final CockpitTranscriptProjection transcript;
  final AgentControlsProjection controls;
  final RelayStatus relayStatus;
  final String? sessionPath;
  final bool pendingLocalSend;

  bool get isBusy => pendingLocalSend || turn.working;
}
```

`WorkspaceDocument` remains the source of tab descriptors and persisted layout. The transcript event log remains the source of user/assistant/thinking/tool transcript entries. `AgentTurnProjection` remains the source of busy/stop/elapsed state. `AgentSession` is left as the pane-local coordinator and process owner until the implementation can safely extract an internal process controller.

## Scan findings and rationale

- **Code smell: fused reducer and process owner.** `agent_session.dart` owns process spawn/kill, RPC command methods, transcript rendering, model controls, relay state, notifications hooks, and turn lifecycle in one class.
- **Missing abstraction: transcript projection exists twice.** `rpc_data_mapper.transcriptMessages()` folds historical messages into mutable `TmTool`s while `AgentSession._onEvent()` folds live events into mutable `ToolEntry`s; history and live streaming can drift.
- **Naming drift: `streaming` means process busy, assistant delta, and stop availability.** `AgentStatus.streaming`, `AgentSnapshot.isStreaming`, `AgentSession.isStreaming`, elapsed timer, tab dot, and composer stop all read the same word with slightly different meanings.
- **Pattern violation: domain transcript models are mutable.** `TmTool` mutates after construction and `ToolEntry` mutates after rendering, making projection rebuilds and replay harder to reason about.
- **Dead-weight candidate: compatibility getters should be temporary.** `status`, `isStreaming`, `turnStartedAt`, and mutable `entries` can stay only while widgets migrate; the final source is `AgentSessionProjection`.
- **Not worth doing here:** changing Pi RPC wire shape, adding a new `turn_state` frame, changing visible transcript UI, or changing the layout persistence version. Those are protocol/product changes, not this refactor.

## Refactor Steps

### Step 1: Define the Cockpit agent-session projection contract
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / naming drift
**Files**: `cockpit/lib/app/cockpit/domain/entities/agent_session_projection.dart`, `cockpit/lib/app/cockpit/domain/entities/agent_snapshot.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/test/domain/agent_session_projection_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-agent-session-step-1`

**Current State**:
```dart
enum AgentStatus { empty, booting, idle, streaming, crashed }

String _title;
AgentStatus _status = AgentStatus.empty;
bool _pendingSend = false;
DateTime? _turnStartedAt;
final List<AgentEntry> _entries = <AgentEntry>[];
AssistantTextEntry? _openText;
ThinkingEntry? _openThinking;
final Map<String, ToolEntry> _openTools = <String, ToolEntry>{};
```

**Target State**:
```dart
AgentSessionProjection _projection = AgentSessionProjection.empty(...);
AgentSessionProjection get projection => _projection;

// Temporary compatibility getters while widgets migrate.
AgentStatus get status => _projection.lifecycle.toLegacyStatus();
bool get isStreaming => _projection.turn.status == AgentTurnStatus.streaming;
DateTime? get turnStartedAt => _projection.turn.startedAt;
List<AgentEntry> get entries => _projection.transcript.entries;
```

**Implementation Notes**:
- Put projection value types in `domain/entities/`; they must not import widgets, process gateways, Hive, or filesystem adapters.
- Reuse the sibling transcript/turn names. If the exact sibling implementation has not landed, create a compatibility adapter with matching names rather than a new Cockpit vocabulary.
- Keep legacy getters side-by-side; no visible UI behavior changes in this step.

**Acceptance Criteria**:
- [ ] Projection types are domain-only and cover lifecycle, transcript, turn, controls, relay status, opaque session id, session path, and pending-send state.
- [ ] `RpcDataMapper.state()` maps legacy `isStreaming` into the projection/turn compatibility path.
- [ ] `AgentSession` exposes the projection plus temporary compatibility getters.
- [ ] Targeted tests cover empty, booting, idle, streaming, pending-send, and crashed snapshots.
- [ ] `flutter test` targeted cockpit tests and `flutter analyze` pass, or blockers are recorded.

**Rollback**: Delete the projection files and revert `AgentSession` / `RpcDataMapper` to direct `AgentStatus` and `AgentSnapshot.isStreaming` fields.

---

### Step 2: Feed AgentSession from the transcript event-log projection
**Priority**: High
**Risk**: Medium
**Source Lens**: missing abstraction / code smell
**Files**: `cockpit/lib/app/cockpit/domain/entities/transcript_message.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/ui/session/agent_entry.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/test/domain/cockpit_transcript_projection_test.dart`, `cockpit/test/data/rpc_data_mapper_transcript_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-agent-session-step-2`

**Current State**:
```dart
final out = <TranscriptMessage>[];
final toolsById = <String, TmTool>{};
...
case 'toolResult':
  final tool = toolsById[raw['toolCallId'] as String? ?? ''];
  if (tool != null) {
    tool.done = true;
    tool.isError = raw['isError'] == true;
    tool.resultText = _contentText(raw['content']);
  }
```

**Target State**:
```dart
final List<CockpitTranscriptEvent> _transcriptEvents = <CockpitTranscriptEvent>[];

void _appendTranscriptEvent(CockpitTranscriptEvent event) {
  _transcriptEvents.add(event);
  _projection = _projection.copyWith(
    transcript: deriveCockpitTranscriptProjection(
      sessionId: _projection.sessionId,
      events: _transcriptEvents,
    ),
  );
}
```

**Implementation Notes**:
- Consume the transcript-event-log projection seam; do not create a parallel event algebra.
- `get_messages` replay and live `_onEvent` must feed the same projection reducer.
- Keep Cockpit control/lifecycle entries (`InfoEntry`, `NoticeEntry`, `UiRequestEntry`) as presenter entries unless the transcript sibling explicitly models them.

**Acceptance Criteria**:
- [ ] Live text/thinking/user/tool RPC events and history replay use one transcript projection path.
- [ ] Mutable `TmTool` / `ToolEntry` state is not domain truth; any remaining mutability is an adapter output.
- [ ] Tests cover replay, streaming delta accumulation, tool collapse, local echo dedupe, and history reload.
- [ ] `flutter test` targeted projection/mapper tests and `flutter analyze` pass, or blockers are recorded.

**Rollback**: Restore `TranscriptMessage` / `TmTool` mutation and the direct `_entries` / `_open*` fold in `AgentSession`.

---

### Step 3: Split process lifecycle from turn projection in AgentSession
**Priority**: High
**Risk**: High
**Source Lens**: code smell / lifecycle convergence
**Files**: `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/lib/app/cockpit/ui/session/agent_process_controller.dart`, `cockpit/lib/app/cockpit/domain/entities/agent_session_projection.dart`, `cockpit/test/ui/agent_session_lifecycle_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-agent-session-step-3`

**Current State**:
```dart
case RpcAgentStart():
  _pendingSend = false;
  _status = AgentStatus.streaming;
  _turnStartedAt = DateTime.now();
case RpcStreamError(:final message):
  _pendingSend = false;
  if (_status == AgentStatus.streaming) _status = AgentStatus.idle;
  _turnStartedAt = null;
```

**Target State**:
```dart
void _onSignal(AgentSessionSignal signal) {
  switch (signal) {
    case AgentTurnSignal(:final event):
      _projection = _projection.copyWith(
        turn: reduceAgentTurn(_projection.turn, event),
      );
    case AgentTranscriptSignal(:final event):
      _appendTranscriptEvent(event);
    case AgentLifecycleSignal(:final lifecycle):
      _projection = _projection.copyWith(lifecycle: lifecycle);
  }
  notifyListeners();
}
```

**Implementation Notes**:
- Preserve `AgentSession` as `PaneItem`/`ChangeNotifier`; split its internals into process-controller effects and projection state.
- Use the turn-state sibling's projection reducer for success, error, abort, process exit, new session, history load, restart, and dispose convergence.
- Keep `onTurnEnd` behavior for notifications/session-path capture.

**Acceptance Criteria**:
- [ ] Process lifecycle and turn projection are separate concepts; `AgentStatus.streaming` is not the turn source.
- [ ] Stop affordance, elapsed timer, and busy state derive from `AgentTurnProjection`.
- [ ] Process subscription/kill/dispose ownership remains explicit and deterministic.
- [ ] Tests cover start/end, stream error, stop/abort, process exit, new session, history load, restart, and dispose.
- [ ] `flutter test` targeted lifecycle tests and `flutter analyze` pass, or blockers are recorded.

**Rollback**: Inline the process controller back into `AgentSession` and restore direct `_status`, `_pendingSend`, and `_turnStartedAt` updates.

---

### Step 4: Realize AgentSession from WorkspaceDocument tab descriptors
**Priority**: High
**Risk**: Medium
**Source Lens**: single source of truth / ports and adapters
**Files**: `cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart`, `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/lib/app/cockpit/domain/entities/workspace_tab.dart`, `cockpit/test/ui/workspace_projection_agent_session_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-agent-session-step-4`

**Current State**:
```dart
AgentSession _buildAgent(String id, Project project, String cwd, { ... }) {
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

**Target State**:
```dart
Future<bool> realizeAgent(WorkspaceTab tab, Project project) async {
  final session = AgentSession.fromWorkspaceTab(
    tab: tab,
    projectId: project.id,
    workingDirectory: cwdFor(tab, project),
    factory: _rpcFactory,
  );
  _items[tab.id] = session;
  await session.boot(restoreSessionPath: tab.sessionPath, environment: _directConfig(session, project));
  return true;
}
```

**Implementation Notes**:
- Consume `WorkspaceTab.agent` descriptors from the workspace-document feature and keep `v: 1` layout JSON unchanged.
- Move agent descriptor projection (`sessionPath`, title, subpath, relay, preferred model/thinking) out of `CockpitViewModel._sessionToJson` and into the live workspace projection adapter.
- Runtime effects (`REMOTE_PI_DIRECT_CONFIG`, session baseline capture, history lookup) remain adapter effects, not document-domain logic.

**Acceptance Criteria**:
- [ ] Agent tabs are realized from and serialized back to `WorkspaceTab.agent` descriptors.
- [ ] `CockpitViewModel` no longer owns agent descriptor serialization directly.
- [ ] Session path/name/preferences/relay changes update the workspace document descriptor and save as before.
- [ ] Existing layout JSON round-trip remains compatible.
- [ ] `flutter test` targeted workspace projection/layout tests and `flutter analyze` pass, or blockers are recorded.

**Rollback**: Restore direct `_buildAgent`, `_restoreSession`, `_sessionToJson`, and `onPreferenceChanged` ownership in `CockpitViewModel`.

---

### Step 5: Migrate UI consumers to the AgentSession projection and retire compatibility state
**Priority**: Medium
**Risk**: Medium
**Source Lens**: dead weight / naming drift
**Files**: `cockpit/lib/app/cockpit/ui/widgets/agent_composer.dart`, `cockpit/lib/app/cockpit/ui/widgets/pane_view.dart`, `cockpit/lib/app/cockpit/ui/widgets/agent_transcript.dart`, `cockpit/lib/app/cockpit/ui/widgets/agent_edit_dialog.dart`, `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/test/ui/agent_session_projection_widget_test.dart`
**Story**: `epic-bold-cockpit-workspace-projection-agent-session-step-5`

**Current State**:
```dart
final streaming = session.isStreaming;
final controlsEnabled = session.isAlive && !streaming;
final active = widget.session.isStreaming && widget.session.turnStartedAt != null;
```

**Target State**:
```dart
final projection = session.projection;
final controlsEnabled = projection.isAlive && !projection.turn.working;
final active = projection.turn.working && projection.turn.startedAt != null;
```

**Implementation Notes**:
- Migrate widgets to `session.projection`, `projection.turn`, and immutable projected transcript entries.
- Remove compatibility getters only after all consumers move.
- Preserve visible labels/behavior; this is source-of-truth cleanup, not UI redesign.

**Acceptance Criteria**:
- [ ] Composer, pane tabs, transcript, edit dialog, and notification count read the projection instead of raw streaming fields/mutable entries.
- [ ] Stop/cancel, controls enabled state, elapsed timer, tab activity indicator, tool card, and notification badge behave as before.
- [ ] `AgentStatus.streaming` / `AgentSnapshot.isStreaming` are removed or documented as wire compatibility with no UI consumers.
- [ ] Targeted tests cover the migrated UI projection paths.
- [ ] `flutter test` targeted cockpit tests, `flutter analyze`, and `dart format .` pass or blockers are recorded.

**Rollback**: Restore legacy getters and UI branches while keeping projection code side-by-side until drift is fixed.

## Implementation Order

1. `epic-bold-cockpit-workspace-projection-agent-session-step-1` — domain projection contract, with external dependency on `workspace-document` and transcript projection.
2. `epic-bold-cockpit-workspace-projection-agent-session-step-2` — live/history transcript inputs feed the transcript-event-log projection.
3. `epic-bold-cockpit-workspace-projection-agent-session-step-3` — process lifecycle split and turn projection consumption.
4. `epic-bold-cockpit-workspace-projection-agent-session-step-4` — workspace document descriptors realize/save agent sessions.
5. `epic-bold-cockpit-workspace-projection-agent-session-step-5` — UI consumers migrate and compatibility state is retired.

## Dependency / cycle check

Manual frontmatter dependency chain is acyclic:

- Step 1: `depends_on: [epic-bold-cockpit-workspace-projection-workspace-document, epic-bold-transcript-event-log-projection-derive]`.
- Step 2: `depends_on: [step-1, epic-bold-transcript-event-log-projection-derive-step-5]`.
- Step 3: `depends_on: [step-2, epic-bold-turn-state-machine-projection-consumers-step-4]`.
- Step 4: `depends_on: [step-3, epic-bold-cockpit-workspace-projection-workspace-document-step-6]`.
- Step 5: `depends_on: [step-4]`.

No active item depended on the new story ids before creation; the parent feature does not depend on its children; all child edges point from later work to earlier/prerequisite work.

## Not worth doing in this feature

- Changing the Pi RPC wire or adding a new `turn_state` frame.
- Redesigning the transcript UI or the workspace tab UI.
- Changing layout persistence version or Hive store signatures.
- Importing mobile `ConnectionManager`, relay room metadata, pairing, crypto, or app Hive transcript storage into Cockpit.
- Baking patchbay-specific assumptions into Cockpit classes; keep the projection names portable so patchbay can replace the process adapter later.

## Review — advanced to done (2026-06-30)

All 5 child steps `done` (projection contract → feed from transcript →
process/turn split → realize from WorkspaceTab → UI migration + compat
retirement). The Cockpit AgentSession is now a projection-coordinated
PaneItem: `AgentProcessController` owns process lifecycle; `AgentSession`
coordinates signals into lifecycle/turn/transcript projections; UI widgets read
the projection directly; mutable compat state retired. Epic complete.
