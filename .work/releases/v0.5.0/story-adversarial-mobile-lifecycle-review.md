---
id: story-adversarial-mobile-lifecycle-review
kind: story
stage: done
tags: [app, pi-extension, relay, workflow]
parent: feature-adversarial-codebase-review
depends_on: []
release_binding: v0.5.0
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Mobile lifecycle / UX adversarial review

Run the mobile lifecycle and UX failure-mode pass for `feature-adversarial-codebase-review`.

## Scope

Review `app/lib/data/transport/`, `app/lib/data/sync/`, `app/lib/ui/`, pairing/storage, app routing/viewmodels, and the `mobile-remote-coding` checklist concerns. Inspect pi-extension/relay only where needed to explain app-visible state.

Bias toward mobile background/resume, reconnect/offline loops, stale cached room/session state, `working`/idle rendering, multi-client state convergence, image/voice/queued-message UX, mounted guards, and silent transport errors.

## Output schema

```markdown
### <short title>
- **Severity**: critical|high|medium|low
- **Confidence**: high|medium|low
- **Evidence**: `path:line` plus quoted/summarized code behavior
- **Failure scenario**: concrete user-visible phone/tablet symptom and event sequence
- **Suggested routing**: patch|refactor|test-only|uncertain
```

## Acceptance Criteria

- [x] Findings include user-visible symptoms on phone/tablet, not only code locations.
- [x] Review identifies whether each issue is app-only, extension-triggered, relay-triggered, or cross-boundary.
- [x] Review calls out missing deterministic tests/smokes for accepted risks.

## Reviewer output — 2026-06-28

Read-only pass completed by subagent `f2158c95-601b-4f9`. No files were edited by the reviewer.

### `working`/streaming state does not converge when the relay WebSocket drops mid-turn
- **Severity**: high
- **Confidence**: high
- **Boundary**: app-only
- **Evidence**: `app/lib/data/sync/sync_service.dart` `_onStatus` cancels the message subscription and writes runtime when leaving `StatusOnline`, but does not call `_setWorking(false)`, `_resetTurnState()`, or clear `_streaming` / `_chunkBuffer` / `_flushTimer` / `_workingReplyTo`.
- **Failure scenario**: relay WebSocket drops while the phone is watching a streamed reply. `ConnectionManager` moves to retry/offline, but chat continues rendering a stale streaming cursor, send remains in stop mode, cancel no-ops because the channel is null, and recovery requires leaving/re-entering chat.
- **Suggested routing**: patch + deterministic test.

### No resume/background re-hydration of room/session state — only mesh polling is lifecycle-bound
- **Severity**: high
- **Confidence**: high
- **Boundary**: app-only
- **Evidence**: `app/lib/main.dart` lifecycle resume only restarts/pulls `MeshSyncService`; no resume hook replays room/presence subscriptions, checks the WebSocket, or requests active chat/session sync. `ConnectionManager._replaySubscriptions()` is only invoked from connect/adopt paths.
- **Failure scenario**: user backgrounds the app during a turn; OS reclaims or half-closes the socket; on resume, chat still appears online/working until ping miss detection or a manual reconnect, with no explicit snapshot request.
- **Suggested routing**: patch + manual phone smoke + deterministic resume-trigger test.

### `_roomsController` stream is never closed in `ConnectionManager.dispose()`
- **Severity**: medium
- **Confidence**: high
- **Boundary**: app-only
- **Evidence**: `app/lib/data/transport/connection_manager.dart` `dispose()` closes `_statusController` and `_presenceController` but not `_roomsController`; grep found no `_roomsController.close()`.
- **Failure scenario**: dependency teardown can leave rooms listeners/controllers alive, allowing late room events against half-disposed services or leaks in tests/app shutdown.
- **Suggested routing**: patch + test.

### Silent drop of malformed/unknown relay frames — no user-visible or metric signal
- **Severity**: medium
- **Confidence**: high
- **Boundary**: app-only with extension/relay-triggered input
- **Evidence**: `app/lib/data/transport/ws_transport.dart` drops unknown/malformed frames with debug-only prints; `app/lib/data/transport/peer_channel.dart` swallows decode failures silently.
- **Failure scenario**: relay/extension sends an unknown upgraded frame or malformed frame during a stream; release build records no durable signal and the user sees missing telemetry or a stalled turn.
- **Suggested routing**: refactor + test-only observability coverage.

### `markRoomWorking` + relay snapshot can diverge, leaving the active room's `working` flag stuck true after a missed `turn_end`
- **Severity**: medium
- **Confidence**: medium
- **Boundary**: cross-boundary
- **Evidence**: `ConnectionManager.markRoomWorking` sets optimistic app-side room working; `RoomMetaUpdated` preserves current working when a patch omits `working`; missed `working:false` broadcast relies on a later `RoomsSnapshot` correction with no app-side timer/snapshot request.
- **Failure scenario**: app backgrounds after optimistic `working:true`; extension clears working but broadcast is missed; resume lacks a forced rooms snapshot; Home/chat can remain stuck working.
- **Suggested routing**: uncertain; likely covered by resume hydration plus a snapshot correction test.

### `clearActiveSession` (`/new`) races with the extension's daemon-respawn contract — no app-side wait for fresh session state
- **Severity**: medium
- **Confidence**: medium
- **Boundary**: cross-boundary
- **Evidence**: `SyncService.clearActiveSession` wipes local state immediately; `ActionsRepository` waits only for `action_ok`; daemon-mode `session_new` may ACK before fresh session state is live; `session_sync` is not gated by a new-session identity threshold before writing rows.
- **Failure scenario**: user taps New Session; app clears local box; old session history arrives during respawn and repopulates cleared chat before fresh empty history arrives.
- **Suggested routing**: uncertain; test stale `SessionHistory.sessionStartedAt` after clear.

### Cancel/stop button can target a stale `inReplyTo` after a steer mid-turn
- **Severity**: low
- **Confidence**: medium
- **Boundary**: app-only
- **Evidence**: `ChatViewModel.cancelTargetId` uses `_streaming?.inReplyTo ?? _sync.workingReplyTo`; steered chunks can update `_workingReplyTo` to the steer id.
- **Failure scenario**: user sends a primary message, then steers mid-turn; stop may cancel the steer id instead of the overall active turn.
- **Suggested routing**: uncertain; clarify intended steer-cancel semantics and test.

## No-finding notes from reviewer

- Offline-loop / retry storm fixes looked sound and tested.
- Pi-liveness vs WebSocket-liveness separation looked sound.
- Session-switch bleed handling looked sound.
- `BuildContext` async safety looked well-guarded in inspected UI.
- `ActionsRepository` pending-completer teardown looked sound.
- Identical `SessionHistory` idempotency looked sound.
- Home filter preservation on status flips looked sound.
- Mesh publish empty-on-existing safety net looked sound.
- Voice/attachment lifecycle disposal looked sound.
- Quick Actions dismissal on session switch looked sound.

## Orchestrator verification targets

1. Deterministically verify `SyncService` clears `isWorking`, `streaming`, and `workingReplyTo` when connection leaves `StatusOnline` mid-turn.
2. Confirm resume currently only restarts mesh polling and decide whether ~50s ping-miss correction is acceptable; run/manual-plan a phone background/resume smoke.
3. Verify `SessionHistory.sessionStartedAt` is not gated after `/new`; test stale history after `clearActiveSession()`.
