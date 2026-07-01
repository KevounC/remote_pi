---
id: epic-bold-turn-state-machine-projection-consumers
kind: feature
stage: done
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-turn-state-machine
depends_on: [epic-bold-turn-state-machine-algebraic-state]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Turn — projection consumers

## Brief
Every consumer of working/turn state becomes a projection of the canonical
`Turn` transition events: pi-extension broadcast (`_broadcastToActive` of
`agent_chunk`/`agent_done`), app working pill (`SyncService._working` /
`_workingReplyTo`), relay `room_meta.working` (merge-patch at
`relay/src/handlers/peer.rs:386-407`), cockpit `AgentStatus`. The "three
loosely-coupled signals converging on `working`" bug class
(`story-mobile-working-status-stuck`) is structurally eliminated — there's one
source.

## Epic context
- Parent epic: `epic-bold-turn-state-machine`
- Position: consumer of `algebraic-state`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:1506-1518` (publishes room meta on turn
  start/end), `app/lib/data/sync/sync_service.dart:960-968` (app local
  correction), `relay/src/handlers/peer.rs:386-407` (relay merge-patch),
  `cockpit/lib/app/cockpit/ui/session/agent_session.dart:1-140`.

## Absorbed from `story-mobile-working-status-stuck` (retired 2026-06-29)

The retired story's reproduction confirms the projection-consumer target: mobile
can continue showing `Working` after the Pi agent is idle. Suspected causes it
documented — all three are the "three loosely-coupled signals converging" the
algebraic turn state machine eliminates:
- Pi publishes `room_meta.working: true` on turn start but misses/loses the
  corresponding false on turn end, errors, session switch, compaction, or
  shutdown.
- Reconnect hydration replays cached `working: true` without authoritative idle
  correction.
- App-side room meta treats `working` as sticky and does not reconcile with
  connection/session lifecycle.

The projection-consumer design must cover all five turn-end paths (end, error,
session switch, compaction, shutdown) and the reconnect-hydration replay as
projection states, not ad-hoc corrections.

<!-- /agile-workflow:refactor-design pins each consumer's projection. -->

## Refactor Overview

The algebraic-state sibling defines the canonical `TurnState`, `TurnSnapshot`,
`reduceTurn`, and `projectTurn` seam. This feature consumes that seam. The
projection shape for all consumers is intentionally small and compatible with the
transcript sibling's `TranscriptTurnView` naming:

```text
TurnConsumerProjection {
  status: idle | working | awaiting_tool | streaming | done | error
  working: boolean              // true only for working/awaiting_tool/streaming
  turnId: string | null         // canonical turn id when known
  replyTo: string | null        // user/client message id answered by this turn
  cancelTargetId: string | null // normally same as replyTo while active
  stale: boolean                // UI-only: transport/session snapshot is not fresh
}
```

`room_meta.working` remains the existing transport compatibility field; it is a
projection of `TurnSnapshot`, not a second state machine. `agent_chunk`,
`agent_done`, mobile chat/home state, relay room snapshots, and Cockpit
`AgentStatus` all derive from the same projected status. No explicit new
`turn_state` wire message is introduced in this refactor; generated-protocol or
patchbay can later lift the projection shape into a schema without a migration
created here.

### Scan findings and rationale

- **Code smell: direct boolean fan-out in `pi-extension/src/index.ts`.**
  `turn_start`, `turn_end`, compaction hooks, and streaming broadcasts mutate or
  read `_myRoomMeta.working` / `_currentTurnId` directly instead of consuming the
  reducer projection.
- **Missing abstraction: mobile has three working sources.** `ChatViewModel.isWorking`
  ORs relay room metadata, `SyncService._working`, and `_streaming != null`; the
  current app-side correction (`ConnectionManager.markRoomWorking`) is useful as
  a backstop but is also a second writer that can become sticky.
- **Lifecycle bug: cached room `working:true` can survive room end.**
  `ConnectionManager.isRoomWorking` gates on `StatusOnline` but does not require
  the room to still be in `_liveRoomIds`, so a cached offline room can still read
  as working after `room_ended` while the relay connection itself is online.
- **Pattern drift: Cockpit names the whole active turn `streaming`.**
  `AgentStatus.streaming`, `AgentSnapshot.isStreaming`, `_pendingSend`, and
  `_turnStartedAt` encode the same turn projection with names that make idle,
  pending-send, tool, error, and shutdown convergence harder to test.
- **Not worth doing here:** a new cross-language `turn_state` protocol frame or
  relay-side interpretation of turn phases would be behavior-changing protocol
  work. This refactor keeps the current wire shape and replaces the sources that
  compute existing UI state.

### Coordination / cycle check

Manual frontmatter cycle check: this feature depends on
`epic-bold-turn-state-machine-algebraic-state`; no active item depends on the new
child story ids before this design. The child stories form a linear acyclic
chain:

`epic-bold-turn-state-machine-algebraic-state -> step-1 -> step-2 -> step-3 -> step-4`.

Step 1 deliberately depends on the algebraic-state feature id, not on one of its
child stories, matching the parent feature boundary the autopilot is draining.

## Refactor Steps

### Step 1: Project pi-extension broadcasts and room metadata from `TurnSnapshot`
**Priority**: High
**Risk**: High
**Source Lens**: code smell / missing abstraction
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/turn_state.ts`, `pi-extension/src/extension.test.ts`
**Story**: `epic-bold-turn-state-machine-projection-consumers-step-1`

**Current State**:
```ts
pi.on("message_update", (event) => {
  if (!_anyPeerActive() || !_currentTurnId) return;
  const ae = event.assistantMessageEvent;
  if (ae.type === "text_delta") {
    _broadcastToActive({ type: "agent_chunk", in_reply_to: _currentTurnId, delta: ae.delta });
  }
});

pi.on("agent_end", () => {
  if (!_currentTurnId) return;
  const finishedTurnId = _currentTurnId;
  if (_anyPeerActive()) {
    _broadcastToActive({ type: "agent_done", in_reply_to: finishedTurnId });
  }
  _currentTurnId = null;
  _finishedTurnIdAwaitingSync = finishedTurnId;
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});

pi.on("turn_start", (_event, ctx) => {
  _turnActive = true;
  _finishedTurnIdAwaitingSync = null;
  _peersAttachedDuringTurn.clear();
  if (_myRoomMeta) _myRoomMeta = { ..._myRoomMeta, working: true };
  if (_relay && _myRoomId) {
    _relay.sendControl({ type: "room_meta_update", room_id: _myRoomId, meta: { working: true } });
  }
});
```

**Target State**:
```ts
function _turnProjection(): TurnProjection {
  return projectTurn(_turn);
}

function _publishTurnProjection(before: TurnProjection, after: TurnProjection): void {
  if (before.working === after.working) return;
  _publishWorking(after.working); // room_meta.working compatibility field
}

function _applyTurnAndPublish(event: TurnEvent): TurnProjection {
  const before = _turnProjection();
  _turn = reduceTurn(_turn, event);
  const after = _turnProjection();
  _publishTurnProjection(before, after);
  return after;
}

pi.on("message_update", (event) => {
  const ae = event.assistantMessageEvent;
  if (ae.type !== "text_delta") return;
  const projection = _applyTurnAndPublish({ type: "agent_chunk", delta: ae.delta });
  const replyTo = projection.replyTo ?? projection.activeTurnId;
  if (!_anyPeerActive() || replyTo === null) return;
  _broadcastToActive({ type: "agent_chunk", in_reply_to: replyTo, delta: ae.delta });
});

pi.on("agent_end", () => {
  const before = _turnProjection();
  const replyTo = before.replyTo ?? before.activeTurnId;
  _applyTurnAndPublish({ type: "agent_done" });
  if (_anyPeerActive() && replyTo !== null) {
    _broadcastToActive({ type: "agent_done", in_reply_to: replyTo });
  }
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});
```

**Implementation Notes**:
- Consume the reducer/projection exported by `epic-bold-turn-state-machine-algebraic-state`; do not recreate a second projection helper in `index.ts`.
- `room_meta.working` is still the public compatibility projection, but every write to it flows through the turn projection diff.
- `agent_chunk`, `agent_done`, cancel target, queued-message drain, and late-attach sync should read `replyTo` / `turnId` from projection selectors rather than from scattered nullable globals.
- Reconnect hello uses cached `_myRoomMeta.working` that was last written by projection. Session shutdown and compaction terminal paths must call the same `_applyTurnAndPublish` path so cached hello cannot replay stale `true`.
- Preserve existing wire messages and timing; duplicate `working:false` control frames are acceptable, but durable `working:true` after a terminal event is not.

**Acceptance Criteria**:
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` and the turn-state test filter pass from `pi-extension/`.
- [ ] No `agent_chunk`, `agent_done`, cancel, queued-drain, or late-attach path reads a raw `_currentTurnId`/`_turnActive`-style global instead of a `TurnProjection` selector.
- [ ] Tests prove `room_meta.working:false` is published or cached after success, provider error, cancel/abort, compaction, session shutdown/replacement, and reconnect hydration.
- [ ] No new `turn_state` wire message is added.

**Rollback**: Revert `index.ts` and tests to the algebraic-state integration baseline. Because the reducer remains side-by-side, rollback should not delete `turn_state.ts` unless the previous sibling is also being reverted.

---

### Step 2: Replace mobile chat working booleans with an app turn projection
**Priority**: High
**Risk**: High
**Source Lens**: missing abstraction / lifecycle convergence
**Files**: `app/lib/domain/session_state.dart`, `app/lib/domain/transcript/transcript_projection.dart`, `app/lib/data/sync/sync_service.dart`, `app/lib/data/transport/connection_manager.dart`, `app/lib/ui/chat/viewmodels/chat_viewmodel.dart`, `app/test/data/sync/sync_service_test.dart`, `app/test/data/transport/connection_manager_test.dart`
**Story**: `epic-bold-turn-state-machine-projection-consumers-step-2`

**Current State**:
```dart
// app/lib/ui/chat/viewmodels/chat_viewmodel.dart
bool get isWorking {
  final epk = _activePeer?.remoteEpk;
  final roomWorking = epk != null && _conn.isRoomWorking(epk, _activeRoomId);
  return roomWorking || _working || _streaming != null;
}

String? get cancelTargetId => _streaming?.inReplyTo ?? _sync.workingReplyTo;
```

```dart
// app/lib/data/sync/sync_service.dart
bool _working = false;
String? _workingReplyTo;

void _setWorking(bool on, {String? preview, String? replyTo}) {
  _setActivity(on ? SessionActivity.working : SessionActivity.idle, preview: preview);
  final epk = _activeEpk;
  if (epk != null) {
    _conn.markRoomWorking(epk, _activeRoomId, on);
  }
  if (on) {
    if (replyTo != null) _workingReplyTo = replyTo;
  } else {
    _workingReplyTo = null;
  }
  if (_working == on) return;
  _working = on;
  if (!_workingController.isClosed) _workingController.add(on);
}
```

**Target State**:
```dart
enum AppTurnStatus { idle, working, awaitingTool, streaming, done, error, stale }

final class AppTurnProjection {
  const AppTurnProjection({
    required this.status,
    this.turnId,
    this.replyTo,
    this.error,
  });

  final AppTurnStatus status;
  final String? turnId;
  final String? replyTo;
  final String? error;

  bool get working => switch (status) {
    AppTurnStatus.working || AppTurnStatus.awaitingTool || AppTurnStatus.streaming => true,
    AppTurnStatus.idle || AppTurnStatus.done || AppTurnStatus.error || AppTurnStatus.stale => false,
  };

  String? get cancelTargetId => working ? replyTo : null;
}

AppTurnProjection deriveChatTurnProjection({
  required RoomTurnProjection room,
  required TranscriptTurnView transcript,
  required StreamingMessage? streaming,
}) { /* room authoritative when fresh; transcript is active-room compat/local optimism */ }
```

```dart
// ChatViewModel reads one projection instead of OR-ing raw sources.
bool get isWorking => _turnProjection.working;
String? get cancelTargetId => _turnProjection.cancelTargetId;
```

**Implementation Notes**:
- Extend the existing transcript sibling seam instead of inventing unrelated names: keep `status`, `turnId`, and `replyTo` aligned with `TranscriptTurnView`.
- `ConnectionManager` should expose a room-level projection (`idle`/`working`/`stale`) rather than a sticky bool. A room not in `_liveRoomIds`, a non-online connection, or a reconnect snapshot not yet hydrated projects `stale`/`idle` with `working:false`.
- `SyncService` may still produce active-room local optimism from `UserMessageSubmitted`, `AgentChunk`, `AgentDone`, `Cancelled`, `Error`, and send-timeout events, but it should publish an `AppTurnProjection`/`TranscriptTurnView` stream rather than `_working` and `_workingReplyTo` as independent mutable fields.
- Remove or narrow `ConnectionManager.markRoomWorking`; if kept temporarily for compatibility, it must update only the active-room projection and must clear on `AgentDone`, error/cancel, non-online status, session switch, and dispose.
- Preserve UI behavior: the chat pill and composer still show working promptly after send and still expose stop/cancel while an active turn exists.

**Acceptance Criteria**:
- [ ] `flutter test test/data/sync/sync_service_test.dart` passes from `app/`.
- [ ] Targeted `ConnectionManager` tests prove `isRoomWorking`/room projection is false when the room is ended, absent from a fresh `RoomsSnapshot`, connection is non-online, or reconnect hydration reports `working:false`.
- [ ] `ChatViewModel.isWorking` and `cancelTargetId` derive from one projection object; they no longer OR `roomWorking || _working || _streaming != null`.
- [ ] `SyncService` convergence tests cover agent done, provider error, cancel/abort, send timeout, compaction/history replay, session switch, connection loss/reconnect, and dispose.
- [ ] The app domain projection imports no Flutter widgets, storage boxes, WebSocket channel, or `BuildContext`.

**Rollback**: Restore the existing `_working` / `_workingReplyTo` stream and `ChatViewModel` OR logic. Keep any pure projection tests if they expose a real convergence bug, but do not weaken them to hide sticky `working:true`.

---

### Step 3: Treat relay room metadata as a projection cache, not an authority
**Priority**: Medium
**Risk**: Medium
**Source Lens**: pattern drift / lifecycle convergence
**Files**: `relay/src/rooms.rs`, `relay/src/handlers/peer.rs`, `relay/src/peers/registry.rs`, `app/lib/protocol/protocol.dart`, `app/lib/data/transport/connection_manager.dart`, `relay/src/peers/registry.rs` tests
**Story**: `epic-bold-turn-state-machine-projection-consumers-step-3`

**Current State**:
```rust
// relay/src/rooms.rs
pub struct RoomMeta {
    pub working: bool,
    pub started_at: i64,
}

pub struct RoomMetaPatch {
    pub working: Option<bool>,
}
```

```rust
// relay/src/handlers/peer.rs
let working_patch = meta_obj
    .and_then(|m| m.get("working"))
    .and_then(|v| v.as_bool());
let patch = RoomMetaPatch {
    model: model_patch,
    thinking: thinking_patch,
    session_id: session_id_patch,
    working: working_patch,
};
```

**Target State**:
```rust
/// Compatibility projection cached by the relay. The pi-extension is the only
/// authority for turn lifecycle; the relay stores and forwards the latest
/// projected boolean for room subscribers and rooms snapshots.
pub struct RoomMeta {
    pub working: bool,
    pub started_at: i64,
}

/// None = absent from patch, Some(false) = terminal/idle projection.
pub struct RoomMetaPatch {
    pub working: Option<bool>,
}
```

```dart
// app-side interpretation of the relay cache.
RoomTurnProjection roomTurnProjection(String epk, String roomId) {
  if (_status is! StatusOnline || !isRoomLive(epk, roomId)) {
    return const RoomTurnProjection(status: AppTurnStatus.stale);
  }
  final room = _roomById(epk, roomId);
  return room?.working == true
      ? const RoomTurnProjection(status: AppTurnStatus.working)
      : const RoomTurnProjection(status: AppTurnStatus.idle);
}
```

**Implementation Notes**:
- Keep relay parsing shape unchanged: `working` is a non-null bool and `false` is the terminal projection.
- Update comments/tests so future agents do not treat relay state as a second turn state machine. The relay should not derive turn phase, reply target, or cancel target.
- `rooms` snapshots are authoritative for currently live rooms; app-side cached rooms missing from the snapshot or ended by `room_ended` must not remain visually working.
- Add relay registry tests for true→false patches, absent `working` preserving current state, `rooms_of` returning the latest projected value, and disconnect/room end causing app projection `working:false` through the live-room gate.
- If Step 2 already moves app interpretation to `RoomTurnProjection`, this step should tighten relay tests and comments rather than churn app code again.

**Acceptance Criteria**:
- [ ] `cargo test` targeted relay registry/room tests pass from `relay/`.
- [ ] Relay tests show `room_meta_updated` broadcasts post-patch `working:false` and that absent `working` does not zero an active projection.
- [ ] App room-projection tests show ended/offline/stale rooms render not-working even if their cached `RoomInfo.working` was last true.
- [ ] No relay code attempts to inspect or synthesize `turnId`, `replyTo`, or phase; it only forwards the projected compatibility bool.
- [ ] `app/lib/protocol/protocol.dart` keeps field names compatible with existing `working` wire frames.

**Rollback**: Revert relay/app interpretation changes to the prior bool cache. Do not remove tests that prove cached ended rooms must not show `working:true`; bounce the story if rollback is needed because that is the absorbed bug class.

---

### Step 4: Project Cockpit agent status from turn state instead of `streaming` flags
**Priority**: Medium
**Risk**: Medium
**Source Lens**: naming inconsistency / missing abstraction
**Files**: `cockpit/lib/app/cockpit/domain/entities/agent_snapshot.dart`, `cockpit/lib/app/cockpit/domain/entities/agent_turn_projection.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`, `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart`, `cockpit/test/` targeted tests
**Story**: `epic-bold-turn-state-machine-projection-consumers-step-4`

**Current State**:
```dart
// cockpit/lib/app/cockpit/ui/session/agent_session.dart
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
// cockpit/lib/app/cockpit/domain/entities/agent_snapshot.dart
class AgentSnapshot {
  const AgentSnapshot({required this.model, required this.thinkingLevel, required this.isStreaming});
  final bool isStreaming;
}
```

**Target State**:
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
// AgentSession projects RPC events into a turn projection.
AgentTurnProjection _turn = const AgentTurnProjection(status: AgentTurnStatus.idle);
bool get isStreaming => _turn.status == AgentTurnStatus.streaming;
bool get isBusy => _turn.working || _pendingSend;
DateTime? get turnStartedAt => _turn.startedAt;
```

**Implementation Notes**:
- Cockpit remains local-only; do not introduce relay, pairing, mobile room metadata, or crypto.
- Keep `AgentStatus` for process lifecycle (`empty`, `booting`, `idle`, `crashed`) or split it from turn status; do not use `streaming` to mean every active turn phase.
- Map `RpcAgentStart`, `RpcTextDelta`, `RpcAgentEnd`, `RpcStreamError`, `RpcProcessExit`, `stop()`, `startNewSession()`, `loadHistory()`, and `killForRestart()` through a small projection reducer/helper so terminal paths converge to `working:false` and `startedAt:null`.
- `RpcDataMapper.state()` should map legacy `isStreaming` into `AgentTurnProjection.streaming` until the pi-extension RPC exposes richer turn projection. Preserve an `isStreaming` compatibility getter if widgets need a staged migration.
- `CockpitViewModel.notificationCount` and tab indicators should read the projected turn status through `AgentSession`, not raw `_status == AgentStatus.streaming` checks.

**Acceptance Criteria**:
- [ ] Targeted cockpit tests cover start→streaming→end, stream error, stop/abort acknowledgement, process exit, session switch/history load, and restart; every terminal path projects not-working and clears `turnStartedAt`.
- [ ] `AgentSnapshot` exposes a turn projection; any remaining `isStreaming` field/getter is documented as temporary compatibility.
- [ ] `AgentSession.isBusy`, composer stop affordance, elapsed timer, and tab indicators derive from `AgentTurnProjection`.
- [ ] `flutter test` targeted cockpit tests pass from `cockpit/`, or a tooling blocker is recorded in the implementing story.
- [ ] No Cockpit code imports mobile app `ConnectionManager`, relay room metadata, or mobile transcript storage.

**Rollback**: Restore `AgentStatus.streaming`, `_pendingSend`, and `_turnStartedAt` as direct UI state in `AgentSession`. Keep the process-lifecycle tests if they expose missing terminal cleanup.

## Implementation Order

1. `epic-bold-turn-state-machine-projection-consumers-step-1` — consume `TurnProjection` in pi-extension broadcast and room-meta publication.
2. `epic-bold-turn-state-machine-projection-consumers-step-2` — introduce the app turn projection and make chat/home working state converge through it.
3. `epic-bold-turn-state-machine-projection-consumers-step-3` — tighten relay room-meta cache semantics and app stale-room interpretation.
4. `epic-bold-turn-state-machine-projection-consumers-step-4` — split Cockpit process lifecycle from turn projection.

## Atomic / rollback notes

No step is intentionally irreversible. Step 1 is the riskiest because it changes
the pi-extension's live broadcast source; keep the wire unchanged and rollback
locally if `agent_chunk`/`agent_done` correlation breaks. Steps 2 and 3 jointly
absorb `story-mobile-working-status-stuck`; if a rollback is needed, preserve the
new convergence tests and bounce the implementation rather than accepting sticky
`working:true`. Step 4 is local to Cockpit and can be reverted without affecting
mobile/relay semantics.

## Refactor-design run notes

- Ambiguity resolved by judgment: the projection-consumer slice remains a
  refactor because it preserves existing wire messages and user-visible states;
  the behavior-changing future (`turn_state` wire frame / generated schema) is
  deferred to generated-protocol or patchbay work.
- Ambiguity resolved by judgment: the relay is a cache/fan-out adapter for
  `room_meta.working`, not an authority. It should not derive phase or reply
  targets.
- Ambiguity resolved by judgment: mobile may keep local optimistic turn feedback,
  but only as a projection (`TranscriptTurnView`/`AppTurnProjection`) with the
  same `status`/`turnId`/`replyTo` names as the transcript and turn-state seams.
- Dispatch rationale: no exploratory subagents were used. The target was a
  bounded set of explicitly named files, the landed sibling designs already
  define the seams, no project refactor-conventions or pattern skills exist, and
  the prior spark-tier attempt failed from context exhaustion rather than missing
  breadth.
