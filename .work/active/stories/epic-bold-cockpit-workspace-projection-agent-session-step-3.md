---
id: epic-bold-cockpit-workspace-projection-agent-session-step-3
kind: story
stage: review
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-agent-session
depends_on: [epic-bold-cockpit-workspace-projection-agent-session-step-2, epic-bold-turn-state-machine-projection-consumers-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 3: Split process lifecycle from turn projection in AgentSession

## Current State

```dart
// cockpit/lib/app/cockpit/ui/session/agent_session.dart
case RpcAgentStart():
  _pendingSend = false;
  _status = AgentStatus.streaming;
  _turnStartedAt = DateTime.now();
case RpcAgentEnd():
  final wasStreaming = _status == AgentStatus.streaming;
  if (wasStreaming) _status = AgentStatus.idle;
  final startedAt = _turnStartedAt;
  _turnStartedAt = null;
  _resetOpenBuffers();
  if (wasStreaming && startedAt != null) {
    _add(WorkedEntry(DateTime.now().difference(startedAt)));
  }
case RpcStreamError(:final message):
  _pendingSend = false;
  if (_status == AgentStatus.streaming) _status = AgentStatus.idle;
  _turnStartedAt = null;
  _addInfo('agent error: $message', isError: true, dedup: true);
case RpcProcessExit(:final code):
  _pendingSend = false;
  _status = AgentStatus.crashed;
  _resetOpenBuffers();
```

## Target State

```dart
final class AgentProcessController {
  AgentProcessController({required RpcGatewayFactory factory});

  Stream<AgentSessionSignal> get signals;
  Future<void> boot(AgentSessionBootRequest request);
  Future<void> send(AgentPrompt prompt);
  Future<void> stop();
  Future<void> killForRestart();
  Future<void> dispose();
}
```

```dart
// AgentSession coordinates process signals into projection updates.
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

## Implementation Notes

- This is not a new process abstraction for all Cockpit panes. Keep it local to agent tabs and backed by the existing `RpcGatewayFactory` / `RpcProcessGateway` port.
- Preserve `AgentSession` as the `PaneItem`/`ChangeNotifier` that widgets listen to. The refactor splits its internals: process controller owns spawn/stdin/subscription/kill, projection owns displayed state.
- Use the `AgentTurnProjection` reducer from the turn-state consumer story for start, text delta, tool wait/result, agent end, stream error, stop/abort acknowledgement, process exit, new session, history load, restart, and dispose convergence.
- Terminal paths must project `working:false` and clear `startedAt`: agent end, stream error, process exit, stop/abort, new session, history load, `killForRestart`, and `dispose`.
- Keep `onTurnEnd` semantics: it fires when a turn transitions from working/streaming to idle/done and still drives session-path capture, git refresh, worktree refresh, and notifications.

## Acceptance Criteria

- [ ] `AgentSession` no longer uses `AgentStatus.streaming` as the turn state; process lifecycle and turn projection are separate concepts.
- [ ] `isBusy`, `isStreaming`, `turnStartedAt`, elapsed timer, stop affordance, and tab activity indicators derive from `AgentTurnProjection` compatibility getters.
- [ ] Process ownership remains explicit: event subscription cancellation, child kill, gateway disposal, and restart teardown stay owned by one controller path.
- [ ] Tests cover start→streaming→end, stream error, stop/abort, process exit, new session, history load, restart, and dispose; every terminal path projects not-working and clears `startedAt`.
- [ ] `onTurnEnd` still fires exactly for successful completed turns that should notify the workspace.
- [ ] `flutter test` targeted cockpit agent-session tests and `flutter analyze` pass, or tooling blockers are recorded.

## Risk

High. This is the core lifecycle extraction and touches process, transcript, notification, and UI busy-state behavior. It must land after the transcript and turn projection seams are available so it does not invent a third state machine.

## Rollback

Inline the process controller back into `AgentSession`, restore direct `_status`, `_pendingSend`, and `_turnStartedAt` updates, and keep the event-log transcript projection from Step 2 if it remains green. If rollback is needed because convergence tests fail, keep those tests and bounce the story rather than weakening them.

## Implementation

- Files changed: `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/lib/app/cockpit/ui/session/agent_process_controller.dart`, `cockpit/lib/app/cockpit/domain/entities/agent_session_signal.dart`, `cockpit/test/ui/agent_session_turn_projection_test.dart`.
- Controller/projection split: added `AgentProcessController` as the local agent-tab process owner for boot, stdin commands, event subscription, process-exit release, restart kill, and dispose. `AgentSession` remains the `PaneItem`/`ChangeNotifier` and coordinates `AgentSessionSignal`s into lifecycle, turn, and transcript projection updates.
- Terminal-path convergence: agent end, stream error, stop/abort acknowledgement, process exit, new session, history load, `killForRestart`, and `dispose` all flow through `AgentTurnProjection` terminal transitions, leaving `working:false` and `startedAt:null`.
- `onTurnEnd` semantics preserved: it fires only when a previously working turn receives a successful `agent_end`; stream error, stop/abort, process exit, and idle `agent_end` do not fire it.
- Tests added/updated: targeted agent-session projection tests now cover start→streaming→end, stream error, stop/abort, process exit, new session, history load, restart, dispose, controller teardown, and `onTurnEnd` success-only semantics.
- UI-identical confirmation: compatibility getters (`isBusy`, `isStreaming`, `turnStartedAt`, `isAlive`) still back existing widgets and now derive from `AgentTurnProjection`/process lifecycle rather than `AgentStatus.streaming`.
- Verification: `flutter pub get --offline`, targeted `flutter test test/ui/agent_session_turn_projection_test.dart`, `flutter analyze`, and full `flutter test` passed.
- Discrepancies from design: controller keeps pass-through wrappers for existing model/session/history/relay RPC commands so stdin ownership stays with the process controller while preserving current `AgentSession` public behavior; no new pane-wide process abstraction was introduced.
- Adjacent issues parked: none.
