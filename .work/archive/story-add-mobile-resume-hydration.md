---
id: story-add-mobile-resume-hydration
kind: story
stage: done
tags: [app, pi-extension, relay]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review, story-fix-mobile-working-convergence-on-disconnect]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Add mobile resume hydration for room/session state

App lifecycle resume currently restarts mesh polling only. It does not explicitly re-check the relay WebSocket, replay presence/room subscriptions, request room snapshots, or request active chat sync.

## Scope

- Add a resume hook that asks connection/session services to reconcile visible state.
- If online, replay subscriptions and request presence/rooms snapshots for known peers; request active session sync.
- If the socket is suspect or retrying, trigger/reuse the normal reconnect path without blocking background/resume handlers.

## Acceptance Criteria

- [x] Deterministic test proves resume triggers room/presence/session hydration even when cached state appears online.
- [x] Manual smoke plan covers background during idle and during working, then foreground.
- [x] No network wait is introduced in pause/background handling.

## Implementation notes

- Added `reconcileOnAppResume(...)` in `app/lib/main.dart` (annotated `@visibleForTesting`) and wired it into `didChangeAppLifecycleState`.
- `resumed` still performs existing mesh polling restart (`startPolling()` + `pullOnDemand()`), then triggers resume reconciliation without awaiting:
  - when `ConnectionManager.status` is `StatusOnline`, replay subscriptions + snapshots for known peers and request a session sync;
  - when status is `StatusRetrying`/`StatusOffline`, reconnect through existing `ConnectionManager.connectTo(activePeer)` and fallback to `boot()`.
- Added `ConnectionManager.requestResumeHydration()` in `app/lib/data/transport/connection_manager.dart` to handle online resume snapshot refresh (reuses known peer list from storage if subscription cache is empty).

## Manual smoke plan

1. Set up two paired peers and verify one visible session tile is idle and one working.
2. Background the app in both states:
   - Case A: no active working turn.
   - Case B: active turn/working visible.
3. During background, force a relay reconnect event (suspend networking or stop/resume the relay).
4. Return app to foreground.
5. Confirm that mesh polling restarts and room/presence snapshots are refreshed via resume hook (no full restart required) and the active session re-syncs:
   - room working/online indicators converge to relay truth,
   - presence map updates are visible,
   - active chat history rehydrates.
6. Confirm pause/inactive/detached path remains unchanged and does not await network calls.

## Review (2026-06-28)

Verdict: Approve

Findings: none.

Verification:
- Reviewed commit `7325228` diff against acceptance criteria.
- Confirmed resume invokes online hydration + session sync, retry/offline uses existing reconnect/boot paths, and pause/inactive/hidden/detached only stop mesh polling without awaiting network work.
- Ran `cd app && /opt/flutter/bin/flutter test --concurrency=1 test/transport/connection_manager_test.dart test/data/sync/sync_service_test.dart test/main_lifecycle_test.dart` (pass).
