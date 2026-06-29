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

## The real problem: intermittent bugs need retroactive capture

The bugs we've found so far (Working stuck, message swallowed, snapshot races)
are intermittent — they surface under real device + network conditions and are
often noticed *after the fact*, not while they're happening. So the question is
not just "can we capture logs" but "can we capture them retroactively, after the
bug already happened."

Surveyed 2026-06-29, the three sides are asymmetric on this:

| Side | Retroactive? | Why |
|---|---|---|
| **Workstation (pi-extension)** | ✅ yes, partially | Append-only `audit.jsonl` at `~/.pi/remote/sessions/<name>/audit.jsonl` (`sessionAuditPath` in `global_config.ts`), tagged with routing (`via=uds` etc.). Survives reboots and time. This is why the swallowed-messages bug was diagnosable after the fact — `[remote-pi] app user_message id=cli_019f10be-…` rejection was in the trail. |
| **Phone (app)** | ❌ no | Only `debugPrint(...)` (`ws_transport.dart`, `sync_service.dart`: `[ws-in]`, `[msg-send] id=…`, `[msg-echo] id=…`) → Android logcat ring buffer. Bounded (~MB), wiped on reboot, rolled over by traffic. No file-based logger; the `logging` package in `pubspec.lock` isn't used for persistent capture. Once the buffer is gone, the bug is invisible. |
| **Relay** | ❌ no | `tracing_subscriber::fmt::init()` → stdout only, run bare (`RUST_LOG=info ./target/release/relay`). No file sink, no journal capture unless the operator redirected it. Gone on scroll/restart. |

**The load-bearing gap is the phone side.** For an intermittent bug noticed after
the fact, today we have the workstation audit trail but *lost the phone and relay
state*. We see what the extension did, not what the phone did or what the relay
actually forwarded. A persistent app-side ring log is what makes intermittent
bugs diagnosable retroactively.

## Raw notes (not a binding plan)

- `adb logcat -s flutter` or `adb logcat | grep -iE "remote_pi|flutter|relay|user_message"`
  is the zero-setup capture-while-it-happens path on USB. Clear first with
  `adb logcat -c`, reproduce, then `adb logcat -d > bug.log`.
- Want the app-side state transitions keyed so they correlate to the relay /
  pi-extension side (shared message id / `session_started_at`).
- Consider whether the existing `flutter-mobile` skill's "Async UI safety" /
  lifecycle logging needs a companion "what to capture when debugging" note.
- Likely near-term slice: persistent app-side ring log (see "good enough"
  above). The other sides can stay as-is until a specific bug forces it.
- **Workstation audit trail is already retroactive** — `audit.jsonl` survives
  across time and reboots. First debugging step for any intermittent bug is to
  read it; the ring-log work is what makes the *phone* side match it.

## Current state of logging across the three surfaces

Surveyed 2026-06-29 (details backing the retroactive-capture table above):

**Relay (Rust, `tracing`)**
- `tracing_subscriber::fmt::init()` in `relay/src/main.rs` — the *default* subscriber, no `EnvFilter`. Logs at the `INFO` level by default; `RUST_LOG=debug` (or `trace`) raises it. No file sink — logs go to stdout/stderr only.
- Already logs structured `peer`/`room`/`addr` fields at `info!` for `authenticated` and `disconnected` events (`relay/src/handlers/peer.rs`), plus the startup `max_ct_bytes` limit. So relay-side correlation by `room_id` already exists at INFO.
- Gap: no per-message-id logging on the forward path (`relay/src/handlers/pi_forward.rs` only `warn!`s on failure). A message that the relay forwards silently has no relay-side trace to correlate against the app's `user_message id=…` or the extension's `app user_message id=…` line. And nothing persisted unless the operator redirected stdout at launch.

**Pi extension (TypeScript)**
- Logs via `console.error` / `console.info` with a `[remote-pi]` prefix, surfaced through the Pi TUI (`ctx.ui.notify`). Operator already saw the key correlation line in the swallowed-messages bug: `[remote-pi] app user_message id=cli_019f10be-…` (`index.ts:3297`). That `id=` is the shared correlation key across app↔extension.
- **Persisted retroactively** via the append-only `audit.jsonl` at `~/.pi/remote/sessions/<name>/audit.jsonl` (`sessionAuditPath` in `global_config.ts`), tagged with routing (`via=uds`). Survives reboots. This is the best of the three sides for after-the-fact diagnosis.
- Gap: no level control / no env flag (no `DEBUG`/`VERBOSE` toggle) on the console surface; everything is at a fixed severity. Verbose state-transition logs (working flips, room snapshot adoption, hydration) are not emitted as such — though the audit trail covers envelope/session-level events.

**App (Flutter)**
- Only `debugPrint(...)` (`ws_transport.dart`, `sync_service.dart`: `[ws-in]`, `[msg-send] id=…`, `[msg-echo] id=…`) → Android logcat ring buffer. Bounded, wiped on reboot, rolled over by traffic. No file-based logger; the `logging` package in `pubspec.lock` is present but not used for persistent capture.
- `adb logcat` is the zero-setup capture-while-it-happens path for USB-connected dev builds.

## What "good enough" looks like (not a binding plan)

Ordered by leverage on the intermittent-bug case:

- **App persistent ring log (highest leverage).** A bounded in-memory ring buffer
  flushed to a file on the device (e.g. `getApplicationDocumentsDirectory`),
  with an in-app "Export debug log" action (share sheet). Captures the
  state-transition lines that map 1:1 to the shipped resilience fixes: `working`
  convergence, room snapshot adoption, reconnect hydration, send-failure
  surfacing, pending-send backstop, stale-session history guards. This is the one
  piece that converts intermittent bugs from "lost" to "diagnosable after the
  fact." `adb logcat -d` remains the zero-setup USB path; the ring log covers the
  non-USB / reboot / buffer-rollover case.
- **Shared correlation key.** The app's `user_message id=…` and the extension's
  `app user_message id=…` already share the message id (extension side at
  `index.ts:3297`). Extending that id (or the `session_started_at` high-water
  `sync_service` already tracks) onto the relay forward path would let a single
  id be grepped across all three sides.
- **Relay:** add a `debug!` (gated behind `RUST_LOG=debug`) on the forward path
  with `peer`, `room`, and the message id, so silent relay drops become visible
  without INFO spam. Separate question: should the relay optionally tee stdout
  to a file/journal so its logs are retroactive too? (Today: only if the
  operator redirected at launch.)
- **Extension:** a lightweight level toggle (env or config) that surfaces the
  state-transition lines above without rewriting the whole logging surface.
  The `audit.jsonl` trail already covers the envelope/routing side.
- Non-goal: structured telemetry / crash reporting service. Start with the ring
  log + `adb logcat` + the existing audit trail; revisit if volume warrants.

## Loop

Operator has the phone paired and can reproduce in real conditions. When a bug
surfaces, grab `adb logcat -d > bug.log` on the phone AND the relay stdout + the
workstation Pi session output (the `[remote-pi] … id=…` lines), then attach all
three to a new `.work/active/stories/` item; scope the debugging slice there
rather than from memory. The shared message id is the join key across sides.
