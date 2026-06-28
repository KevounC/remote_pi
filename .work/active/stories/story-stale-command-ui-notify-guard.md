---
id: story-stale-command-ui-notify-guard
kind: story
stage: drafting
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-stale-session-bound-surface-deep-audit]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Guard command UI notifications against stale contexts after awaits

## Brief

The deep stale-session-bound audit found the main remaining stale SDK surface: many command helpers call raw `ctx.ui.notify(...)` after one or more `await`s. If session replacement lands while the command is in flight, the captured command context can become stale and a post-await notify can throw the same stale-context error class.

## Evidence

Representative areas from `pi-extension/src/index.ts`:

- `_cmdRoot` wizard/setup path around config save + join/start/status.
- `_cmdSetup` after `runSetupWizard(...)`.
- `_cmdStart` keyring/relay connection paths, though relay-connect failure is partly guarded by `_notify(..., ctx)`.
- `_cmdPair`, `_cmdStop`, `_cmdRevoke` after storage/relay operations.
- Fleet daemon and cron commands after supervisor RPC calls.
- `_notifyOffline` and other helper paths that may run after async command work.

## Expected fix shape

- Introduce or consistently use a safe command notification helper that catches stale UI access and clears captured slots when applicable.
- Replace post-await raw `ctx.ui.notify(...)` call sites with the safe helper where session replacement can occur between the command start and notification.
- Keep purely immediate command validation notifications simple if they cannot cross an async gap, but prefer consistency where noise is low.

## Acceptance

- Add at least one delayed-await regression for `_cmdPair` or `_cmdRevoke`: pause an awaited dependency, fire `session_shutdown`, resume dependency, assert no stale UI throw.
- Add at least one daemon/supervisor delayed-await regression or record why daemon commands are not session-bound in this path.
- Full `pi-extension` verification passes.
