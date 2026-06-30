---
id: epic-bold-cockpit-workspace-projection-agent-session-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-cockpit-workspace-projection-agent-session
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document, epic-bold-transcript-event-log-projection-derive]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 1: Define the Cockpit agent-session projection contract

## Current State

```dart
// cockpit/lib/app/cockpit/ui/session/agent_session.dart
enum AgentStatus { empty, booting, idle, streaming, crashed }

String _title;
AgentStatus _status = AgentStatus.empty;
bool _pendingSend = false;
final List<String> _awaitingUserEcho = <String>[];
DateTime? _turnStartedAt;
final List<AgentEntry> _entries = <AgentEntry>[];
AssistantTextEntry? _openText;
ThinkingEntry? _openThinking;
final Map<String, ToolEntry> _openTools = <String, ToolEntry>{};
```

```dart
// cockpit/lib/app/cockpit/domain/entities/agent_snapshot.dart
class AgentSnapshot {
  const AgentSnapshot({
    required this.model,
    required this.thinkingLevel,
    required this.isStreaming,
  });

  final PiModel? model;
  final ThinkingLevel thinkingLevel;
  final bool isStreaming;
}
```

## Target State

```dart
// cockpit/lib/app/cockpit/domain/entities/agent_session_projection.dart
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
  bool get isAlive => lifecycle == AgentProcessLifecycle.idle ||
      lifecycle == AgentProcessLifecycle.running;
}

enum AgentProcessLifecycle { empty, booting, idle, running, crashed }
```

```dart
// cockpit/lib/app/cockpit/ui/session/agent_session.dart
AgentSessionProjection _projection = AgentSessionProjection.empty(...);
AgentSessionProjection get projection => _projection;

// Temporary compatibility getters while widgets migrate.
AgentStatus get status => _projection.lifecycle.toLegacyStatus();
bool get isStreaming => _projection.turn.status == AgentTurnStatus.streaming;
DateTime? get turnStartedAt => _projection.turn.startedAt;
List<AgentEntry> get entries => _projection.transcript.entries;
```

## Implementation Notes

- Define the projection in `domain/entities/` so it can be consumed by `AgentSession`, `WorkspaceProjection`, tests, and a future patchbay presenter without importing widgets, Hive, `RpcProcessGateway`, or `dart:io`.
- Reuse the transcript-event-log sibling's Cockpit transcript projection types and field names (`TranscriptEvent`, `TranscriptTurnView`, `status`, `turnId`, `replyTo`). Do not invent a second transcript algebra in this feature.
- Reuse or adapt the turn-state sibling's `AgentTurnProjection` for `turn`; if that story has not landed, create a tiny compatibility adapter with the same names and a TODO-free migration note in this story body before review.
- Keep `AgentStatus`, `isStreaming`, `turnStartedAt`, and `entries` as compatibility getters during implementation. Widgets move later; this step should not change visible behavior.
- Include mapper tests for legacy `AgentSnapshot.isStreaming` into `AgentTurnProjection.streaming` so `get_state` remains backward-compatible.

## Acceptance Criteria

- [ ] `AgentSessionProjection` and supporting value types live under `cockpit/lib/app/cockpit/domain/entities/` and import no UI, process, Hive, filesystem, or Flutter widget APIs.
- [ ] The projection has one place for lifecycle, transcript, turn, controls, relay status, opaque session id, session path, and pending-send state.
- [ ] `AgentSession` exposes the projection plus temporary compatibility getters without changing UI behavior.
- [ ] `RpcDataMapper.state()` maps legacy `isStreaming` into the projection/turn compatibility path.
- [ ] Targeted domain/mapper tests cover empty, booting, idle, streaming, pending-send, and crashed snapshots.
- [ ] `flutter test` targeted cockpit tests and `flutter analyze` pass, or tooling blockers are recorded in the story.

## Risk

Medium. The projection type is new and side-by-side, but it names state that many widgets already read through legacy getters. The main risk is accidentally changing `isBusy` / `isAlive` semantics.

## Rollback

Delete `agent_session_projection.dart` and revert `AgentSession` / `RpcDataMapper` to direct `AgentStatus` and `AgentSnapshot.isStreaming` fields. Since this step is side-by-side, rollback should not affect persisted layouts or process behavior.

## Implementation

- Added `cockpit/lib/app/cockpit/domain/entities/agent_session_projection.dart` as the side-by-side domain projection contract. It owns tab/project identity, title, process lifecycle, reused `AgentTurnProjection`, reused `CockpitTranscriptProjection`, controls, relay status, opaque/session path fields, and pending-local-send state without importing UI, Hive, filesystem, process, or Flutter widget APIs.
- Reused the landed turn and transcript projection contracts: `AgentSessionProjection.turn` is `AgentTurnProjection`, and `AgentSessionProjection.transcript` is the existing Cockpit transcript projection from `transcript_message.dart`; no second turn or transcript algebra was introduced.
- `AgentSession` now exposes `projection` and routes the temporary compatibility getters (`status`, `turn`, `isStreaming`, `turnStartedAt`, `isBusy`, `isAlive`, controls) through that projection while keeping the legacy `entries` list as the UI-compatible AgentEntry adapter. Current repo reality already had `AgentStatus` as `empty/booting/idle/crashed`; `AgentProcessLifecycle.running` maps back to legacy `idle` so visible UI behavior remains unchanged.
- `RpcDataMapper.state()` already maps legacy `isStreaming` into `AgentTurnProjection.streaming` from the landed dependency; targeted mapper tests remain in `rpc_data_mapper_transcript_projection_test.dart` and were run with this story.
- Added tests for empty, booting, idle, streaming, pending-send, and crashed projection snapshots plus an `AgentSession` compatibility test proving `isBusy`/`isAlive` match the new projection through pending-send, working, and crashed states.
- Verification: `flutter pub get --offline`; targeted `flutter test test/domain/agent_session_projection_test.dart test/ui/agent_session_turn_projection_test.dart test/data/rpc_data_mapper_transcript_projection_test.dart` (21/21); `flutter analyze` (0 issues); full `flutter test` (210/210).

## Review

Approved (2026-06-30). Independently re-ran: whole-cockpit `flutter analyze` →
No issues found; full `flutter test` → 210/210 (incl. 7 new projection tests).
Commit `0e920a0` scoped to cockpit only (new agent_session_projection.dart +
agent_session compat getters + 2 test files + story .md); no cross-subproject
collision. Ports & adapters verified: `agent_session_projection.dart` imports
ONLY domain entities (no UI/Hive/process/Flutter widget APIs). Reused (not
forked) `AgentTurnProjection` + Cockpit transcript projection — no second
algebra. `isBusy`/`isAlive` semantics preserved (compat-getter test proves it
across pending-send/working/crashed states); `AgentProcessLifecycle.running`
maps to legacy `idle` to keep visible UI behavior unchanged. Targeted snapshot
tests cover empty/booting/idle/streaming/pending-send/crashed.
