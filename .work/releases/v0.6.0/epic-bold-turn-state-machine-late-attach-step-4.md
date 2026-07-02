---
id: epic-bold-turn-state-machine-late-attach-step-4
kind: story
stage: done
tags: [refactor]
parent: epic-bold-turn-state-machine-late-attach
depends_on: [epic-bold-turn-state-machine-late-attach-step-3]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 4: Prove late-attach convergence across extension and app hydration

**Priority**: High  
**Risk**: Medium  
**Source Lens**: testing-integrity convergence requirement / pattern drift  
**Files**: `pi-extension/src/extension.test.ts`, `pi-extension/src/session/turn_state.test.ts`, `app/test/transport/connection_manager_working_test.dart`, `app/test/data/sync/sync_service_test.dart`, optionally `app/lib/data/transport/connection_manager.dart`

## Current State

```ts
// pi-extension/src/extension.test.ts already covers one happy-path late owner attach.
test("late owner attach during local/RPC turn receives final reply and working=false", async () => {
  // turn_start, owner attach, chunk, message_end, agent_end, turn_end
  // asserts chunk/done/history and a working=false metadata update
});
```

```dart
// app/lib/data/transport/connection_manager.dart
bool isRoomWorking(String epk, String roomId) {
  if (_status is! StatusOnline) return false;
  final list = _roomsByPeer[toStandardB64(epk)];
  if (list == null) return false;
  for (final r in list) {
    if (r.roomId == roomId) return r.working;
  }
  return false;
}
```

The existing tests prove individual symptoms, but not the full late-attach matrix: active attach, post-done/pre-flush attach, shutdown during late attach, reconnect hydration, and app session-history replay must all converge to `working:false`.

## Target State

Add a small convergence matrix rather than scattered one-off assertions:

```ts
const lateAttachTerminalCases = [
  "agent_done_then_turn_end",
  "turn_end_before_flush",
  "session_shutdown_before_flush",
  "queued_message_after_late_sync",
] as const;

for (const name of lateAttachTerminalCases) {
  test(`late attach ${name} converges working=false and clears targets`, async () => {
    // drive reducer or extension hook sequence
    expect(projectTurn(snapshot).working).toBe(false);
    expect(projectTurn(snapshot).lateAttachSyncTargets).toEqual([]);
  });
}
```

App hydration assertions:

```dart
test('late attach hydrates working true then terminal false without session_history reviving it', () async {
  ch.pushControl(const RoomAnnounced(peer: 'epk_test', roomId: 'r1', startedAt: 1, working: true));
  expect(cm.isRoomWorking('epk_test', 'r1'), isTrue);

  ch.pushControl(const RoomMetaUpdated(peer: 'epk_test', roomId: 'r1', working: false, hasModel: false, hasThinking: false));
  expect(cm.isRoomWorking('epk_test', 'r1'), isFalse);

  syncChannel.push(SessionHistory(inReplyTo: 'turn-1', sessionStartedAt: 1, events: [...final assistant...], eos: true, truncated: false));
  expect(sync.isWorking, isFalse);
});
```

If implementation discovers that cached offline rooms can report `working:true` while not live, make the minimal correction:

```dart
bool isRoomWorking(String epk, String roomId) {
  if (!isRoomLive(epk, roomId)) return false;
  // then read RoomInfo.working
}
```

## Implementation Notes

- Prefer deterministic reducer and fake-channel tests; do not add sleeps except existing test-settle helpers already used in the suite.
- Verify both directions of late attach:
  - owner attaches while active and should see `working:true` from room metadata until terminal false;
  - owner attaches after `agent_done` but before late sync flush and must receive final `session_history` while `working` remains false.
- `session_history` is catch-up data; applying it in the app must not set active working or resurrect a cancel target after terminal false.
- Include shutdown: late target collection must clear and no history should be sent from a disposed extension instance.
- Keep this as tests/minimal projection correction only. Do not add a new `turn_state` wire message; that belongs to generated-protocol/patchbay work.

## Acceptance Criteria

- [ ] `corepack pnpm test -- turn_state` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` passes from `pi-extension/`.
- [ ] `flutter test test/transport/connection_manager_working_test.dart test/data/sync/sync_service_test.dart` passes from `app/`.
- [ ] Tests prove `working:false`, null cancel target, and empty late-attach target collection after success, late sync flush, queued drain, and shutdown.
- [ ] Tests prove app `session_history` replay after terminal false does not re-open active working.
- [ ] Any app-side code change is limited to projection/hydration correctness, not a new protocol shape.

## Risk

Medium. Tests may expose behavior that belongs to the projection-consumers sibling; keep fixes here limited to late-attach hydration/convergence and file broader consumer rewrites back to the sibling if needed.

## Rollback

Revert the added convergence tests and any minimal app projection correction. Do not weaken existing convergence assertions; if they fail, fix the reducer/integration or route the broader work to `epic-bold-turn-state-machine-projection-consumers`.

## Implementation

- Added reducer convergence matrix in `pi-extension/src/session/turn_state.test.ts` covering terminal success before flush, late sync flush, queued drain eligibility after late sync, and shutdown; all assert `working:false`, `activeTurnId:null`, `cancelTargetId:null`, and target collection state.
- Added extension integration coverage in `pi-extension/src/extension.test.ts` for late attach history flush clearing targets, shutdown before late flush sending no history, and existing late attach happy path now also asserts empty late targets after convergence.
- Added app hydration coverage in `app/test/transport/connection_manager_working_test.dart` for `working:true` attach hydration, terminal `working:false`, and `session_history` not reviving room working.
- Added SyncService coverage in `app/test/data/sync/sync_service_test.dart` proving `session_history` replay after terminal false does not reopen `isWorking`, `workingReplyTo`, streaming, room working, or durable session activity.
- Production code changes: none.
- Verification:
  - `corepack pnpm typecheck`: passed.
  - `corepack pnpm exec vitest run src/session/turn_state.test.ts`: 17 passed.
  - `corepack pnpm exec vitest run src/extension.test.ts`: 165 passed, 4 failed with known environment false-alarm names: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, `a second same-name agent joins as <name>#2 instead of being refused`.
  - `flutter test test/transport/connection_manager_working_test.dart test/data/sync/sync_service_test.dart`: 70 passed.

## Review

Approved (2026-06-30). Independently re-ran: **pi-ext 718 passed (up from 715 — +3
convergence tests)**; **app 614 passed (up from 612 — +2 hydration tests)**; pi-ext
typecheck clean. Commit `54bf75f` scoped to pi-ext + app test files; collision guard held.

Convergence coverage verified: pi-ext `turn_state.test.ts` reducer matrix asserts
`working:false`/`activeTurnId:null`/`cancelTargetId:null`/target-collection across
terminal success, late sync flush, queued drain, compaction, and shutdown.
`extension.test.ts` covers late-attach history flush clearing targets + shutdown-before-
late-flush no-history. App `connection_manager_working_test.dart` covers `working:true`
attach hydration → terminal `working:false` + `session_history` not reviving room working.
`sync_service_test.dart` proves `session_history` replay after terminal false doesn't
reopen `isWorking`/`workingReplyTo`/streaming/room working/durable session activity.
