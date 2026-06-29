---
id: idea-phone-log-pipeline-for-debug
created: 2026-06-29
updated: 2026-06-29
tags: [app, pi-extension, debug]
---

# Phone-side log pipeline for debugging live mobile-session bugs

Now that the debug APK can be built and side-loaded to a real device (see archived
`story-remote-pi-android-build-smoke`), the next capability gap is *capturing
phone-side logs* when an oddity surfaces during real use, so we can map a live
symptom back to the app/extension/relay path that produced it.

## Why now

The mobile resilience fixes we just shipped (`story-fix-mobile-working-convergence-on-disconnect`,
`story-add-mobile-resume-hydration`, `story-fix-room-switch-snapshot-adoption`,
`story-fix-mobile-message-send-failures-visible`, the pending-send backstop, the
stale-session history guards) are all correctness/convergence work whose failure
modes only show up under real device + network conditions — disconnects, app
backgrounding, reconnect races. Reproducing them in a unit test is hard; a phone
log captured at the moment the user sees the bug is the highest-value signal.

## Raw notes (not a binding plan)

- Collect a phone-side log capture path so a user reporting "Working stuck" or
  "message swallowed" can ship logs we can actually read.
- Likely surface: `adb logcat` over USB for dev builds, and/or an in-app log
  buffer the app can export/share on demand (for non-USB cases).
- Want app-side state transitions in the logs: `working` convergence, room
  snapshot adoption, reconnect hydration, send-failure surfacing, pending-send
  backstop — keyed so they correlate to the relay/pi-extension side.
- Correlate phone logs with the workstation/relay side (`[remote-pi] app user_message id=...`
  lines, room_meta working flips) via shared message ids / session_started_at.
- Consider whether the existing `flutter-mobile` skill's "Async UI safety" /
  lifecycle logging needs a companion "what to capture when debugging" note.
- Non-goal here: structured telemetry / crash reporting service. Start with
  developer-facing `adb logcat` + an in-app export; revisit if volume warrants.

## Loop

Operator has the phone paired and can reproduce in real conditions. When a bug
surfaces, grab `adb logcat` (filtered to the app package / relay WS tags) and
attach to a new `.work/active/stories/` item; scope the debugging slice there
rather than from memory.
