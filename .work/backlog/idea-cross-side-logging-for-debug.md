---
id: idea-cross-side-logging-for-debug
created: 2026-06-29
updated: 2026-06-29
tags: [app, pi-extension, relay, debug]
---

# Cross-side logging for debugging live mobile-session bugs

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

## Current state of logging across the three surfaces

Surveyed 2026-06-29 so the gap is concrete, not assumed:

**Relay (Rust, `tracing`)**
- `tracing_subscriber::fmt::init()` in `relay/src/main.rs` — the *default* subscriber, no `EnvFilter`. Logs at the `INFO` level by default; `RUST_LOG=debug` (or `trace`) raises it. No file sink — logs go to stdout/stderr only.
- Already logs structured `peer`/`room`/`addr` fields at `info!` for `authenticated` and `disconnected` events (`relay/src/handlers/peer.rs`), plus the startup `max_ct_bytes` limit. So relay-side correlation by `room_id` already exists at INFO.
- Gap: no per-message-id logging on the forward path (`relay/src/handlers/pi_forward.rs` only `warn!`s on failure). A message that the relay forwards silently has no relay-side trace to correlate against the app's `user_message id=…` or the extension's `app user_message id=…` line.

**Pi extension (TypeScript)**
- Logs via `console.error` / `console.info` with a `[remote-pi]` prefix, surfaced through the Pi TUI (`ctx.ui.notify`). Operator already saw the key correlation line in the swallowed-messages bug: `[remote-pi] app user_message id=cli_019f10be-…`. That `id=` is the shared correlation key across app↔extension.
- Gap: no level control / no env flag (no `DEBUG`/`VERBOSE` toggle); everything is at a fixed severity. No structured logger — just prefixed strings. Verbose state-transition logs (working flips, room snapshot adoption, hydration) are not emitted today.

**App (Flutter)** — covered in the phone-log section above; `adb logcat` is the zero-setup capture path for now.

## What "good enough" looks like (not a binding plan)

- **Shared correlation key.** The app's `user_message id=…` and the extension's `app user_message id=…` already share the message id. Extending that id (or the `session_started_at` high-water the sync_service already tracks) onto the relay forward path would let a single id be grepped across all three sides.
- **Relay:** add a `debug!` (gated behind `RUST_LOG=debug`) on the forward path with `peer`, `room`, and the message id, so silent relay drops become visible without spamming at INFO.
- **Extension:** a lightweight level toggle (env or config) that surfaces state-transition lines — `working` flips, room snapshot adoption, reconnect hydration, pending-send backstop — without rewriting the whole logging surface. These map 1:1 to the recently-shipped resilience fixes.
- **App:** the in-app log export for the non-USB case (phone-log section above) is the missing piece; `adb logcat` covers the USB case today.

## Loop

Operator has the phone paired and can reproduce in real conditions. When a bug
surfaces, grab `adb logcat -d > bug.log` on the phone AND the relay stdout + the
workstation Pi session output (the `[remote-pi] … id=…` lines), then attach all
three to a new `.work/active/stories/` item; scope the debugging slice there
rather than from memory. The shared message id is the join key across sides.
