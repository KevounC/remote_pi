---
id: story-fix-mobile-message-send-failures-visible
kind: story
stage: review
tags: [bug, app]
parent: null
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Surface mobile message send failures visibly

## Symptom

Backlog bug `bug-mobile-messages-swallowed-silently` reports that mobile messages can appear to disappear without an obvious error or recovery signal. The live stale-context path can return an `internal_error`, but the app also has a no-echo send timeout path that removes optimistic pending messages silently.

## Root cause

`SyncService.sendMessage()` writes an optimistic pending user row and waits for the Pi echo to confirm delivery. If no echo arrives, `_onSendTimeout()` deletes the pending row without writing any visible failure record. If the channel send itself throws, the optimistic row can also sit pending until the silent timeout reaps it. Both paths make accepted-looking mobile sends look swallowed.

## Fix approach

Keep the existing pending-row timeout as the backstop, but replace silent reaping with a visible assistant error row. Also catch immediate channel send failures, clear the optimistic/streaming/working state for that send, and write the same visible failure surface instead of relying on an unobserved Future error.

## Regression test

Update `app/test/data/sync/sync_service_test.dart` so no-echo timeout, offline held-pending timeout, stale pending rows reloaded after timeout, and immediate channel send failure all produce visible error rows instead of silently disappearing.

## Implementation notes

- Changed `app/lib/data/sync/sync_service.dart` so failed/potentially swallowed sends call `_failPendingSend()`.
- No-echo timeouts now remove only the pending optimistic user row and insert a visible assistant error row (`⚠ send_timeout: ...`).
- Immediate `IChannel.send()` failures now insert a visible assistant error row (`⚠ send_error: ...`), clear the owned streaming/working state, and cancel that send's timer.
- Timeout callbacks carry the owning `(peer, room)` snapshot so a late timer cannot write the failure into a newly active chat.
- Updated `app/test/data/sync/sync_service_test.dart` expectations and added a send-throw regression.

## Verification

- `git diff --check` passed.
- Installed Flutter 3.44.4 locally under `~/tools/flutter` for this environment.
- `flutter test --no-pub test/data/sync/sync_service_test.dart --plain-name "no-echo send timeout"` passed.
- `flutter analyze --no-pub --no-fatal-infos` passed with one existing SDK-skew info: `SizeTransition.axisAlignment` deprecation in `app/lib/ui/chat/widgets/input_bar.dart`. The local source already documents that this is intentionally retained for the Flutter 3.41.7 CI pin and should not be changed without bumping the pin.

## Acceptance

- [x] Missing Pi echo produces a visible failure row instead of silently deleting the user's pending message.
- [x] Immediate channel send failures produce a visible failure row and clear local working/streaming state.
- [x] Offline/reloaded pending rows time out into visible failures instead of disappearing.
- [x] Targeted Flutter regression test passes in an environment with Flutter installed.
