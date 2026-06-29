---
id: epic-bold-turn-state-machine-projection-consumers-step-4
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-turn-state-machine-projection-consumers
depends_on: [epic-bold-turn-state-machine-projection-consumers-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Project Cockpit agent status from turn state instead of `streaming` flags

**Priority**: Medium
**Risk**: Medium
**Source Lens**: naming inconsistency / missing abstraction
**Files**: `cockpit/lib/app/cockpit/domain/entities/agent_snapshot.dart`, `cockpit/lib/app/cockpit/domain/entities/agent_turn_projection.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/test/` targeted tests

## Current State

```dart
enum AgentStatus { empty, booting, idle, streaming, crashed }

bool _pendingSend = false;
DateTime? _turnStartedAt;

bool get isStreaming => _status == AgentStatus.streaming;
bool get isBusy => _status == AgentStatus.streaming || _pendingSend;

case RpcAgentStart():
  _pendingSend = false;
  _status = AgentStatus.streaming;
  _turnStartedAt = DateTime.now();
case RpcAgentEnd():
  final wasStreaming = _status == AgentStatus.streaming;
  if (wasStreaming) _status = AgentStatus.idle;
  _turnStartedAt = null;
case RpcStreamError(:final message):
  _pendingSend = false;
  if (_status == AgentStatus.streaming) _status = AgentStatus.idle;
  _turnStartedAt = null;
```

```dart
class AgentSnapshot {
  const AgentSnapshot({required this.model, required this.thinkingLevel, required this.isStreaming});
  final bool isStreaming;
}
```

## Target State

```dart
enum AgentTurnStatus { idle, working, streaming, error, stale }

final class AgentTurnProjection {
  const AgentTurnProjection({required this.status, this.turnId, this.replyTo, this.startedAt, this.error});
  final AgentTurnStatus status;
  final String? turnId;
  final String? replyTo;
  final DateTime? startedAt;
  final String? error;

  bool get working => status == AgentTurnStatus.working || status == AgentTurnStatus.streaming;
  bool get canStop => working;
}

class AgentSnapshot {
  const AgentSnapshot({required this.model, required this.thinkingLevel, required this.turn});
  final PiModel? model;
  final ThinkingLevel thinkingLevel;
  final AgentTurnProjection turn;

  bool get isStreaming => turn.status == AgentTurnStatus.streaming; // temporary UI compatibility getter
}
```

```dart
AgentTurnProjection _turn = const AgentTurnProjection(status: AgentTurnStatus.idle);
bool get isStreaming => _turn.status == AgentTurnStatus.streaming;
bool get isBusy => _turn.working || _pendingSend;
DateTime? get turnStartedAt => _turn.startedAt;
```

## Implementation Notes

- Cockpit remains local-only; do not introduce relay, pairing, mobile room metadata, or crypto.
- Keep `AgentStatus` for process lifecycle (`empty`, `booting`, `idle`, `crashed`) or split it from turn status; do not use `streaming` to mean every active turn phase.
- Map `RpcAgentStart`, `RpcTextDelta`, `RpcAgentEnd`, `RpcStreamError`, `RpcProcessExit`, `stop()`, `startNewSession()`, `loadHistory()`, and `killForRestart()` through a small projection reducer/helper so terminal paths converge to `working:false` and `startedAt:null`.
- `RpcDataMapper.state()` should map legacy `isStreaming` into `AgentTurnProjection.streaming` until the pi-extension RPC exposes richer turn projection. Preserve an `isStreaming` compatibility getter if widgets need a staged migration.
- `CockpitViewModel.notificationCount` and tab indicators should read the projected turn status through `AgentSession`, not raw `_status == AgentStatus.streaming` checks.

## Acceptance Criteria

- [ ] Targeted cockpit tests cover start→streaming→end, stream error, stop/abort acknowledgement, process exit, session switch/history load, and restart; every terminal path projects not-working and clears `turnStartedAt`.
- [ ] `AgentSnapshot` exposes a turn projection; any remaining `isStreaming` field/getter is documented as temporary compatibility.
- [ ] `AgentSession.isBusy`, composer stop affordance, elapsed timer, and tab indicators derive from `AgentTurnProjection`.
- [ ] `flutter test` targeted cockpit tests pass from `cockpit/`, or a tooling blocker is recorded in the implementing story.
- [ ] No Cockpit code imports mobile app `ConnectionManager`, relay room metadata, or mobile transcript storage.

## Rollback

Restore `AgentStatus.streaming`, `_pendingSend`, and `_turnStartedAt` as direct UI state in `AgentSession`. Keep the process-lifecycle tests if they expose missing terminal cleanup.
