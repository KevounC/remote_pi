---
id: story-remote-pi-stale-context-source-fix
kind: story
stage: done
tags: [pi-extension, bug]
parent: feature-remote-pi-fork-vendor-and-mobile-surface
depends_on: [story-remote-pi-local-vendor-switch, story-remote-pi-stale-context-investigation]
release_binding: extension-0.5.4
gate_origin: null
created: 2026-06-27
updated: 2026-06-27
---

# Port remote-pi stale-context crash fix into fork source

## Brief

Move the local installed-package hotfix into `/home/agent/forks/remote_pi/pi-extension/src/` so the
fix survives package reinstall/update and can be proposed upstream. This patch should follow the
findings from [`story-remote-pi-stale-context-investigation`](story-remote-pi-stale-context-investigation.md)
so we do not land a speculative guard while the live failure is still ambiguous.

## Crash grounding

Observed Pi uncaught exception after reconnect/session replacement:

```text
Error: This extension ctx is stale after session replacement or reload.
    at ExtensionRunner.assertActive (.../runner.js:331:19)
    at get ui (.../runner.js:416:24)
    at _refreshFooter (.../remote-pi/dist/index.js:197:22)
    at _attachOwner (.../remote-pi/dist/index.js:808:5)
    at RelayClient.onMsg (.../remote-pi/dist/index.js:871:29)
```

Related app-facing error:

```text
internal_error: Agent rejected incoming message: This extension ctx is stale after session replacement or reload.
```

## Fix direction

- Do not use captured command/base contexts after `session_shutdown`, session replacement, or reload.
- Route footer/status/notify through a safe helper that catches stale-context access and falls back to
  the freshest `session_start` context where possible.
- Clear captured command context on `session_shutdown`; only re-capture command-capable context from
  explicit command handlers or `withSession` replacement callbacks.
- Wrap late `pi.sendMessage` / `pi.sendUserMessage` calls so stale session-bound sends fail closed or
  use a fresh replacement-session context when one exists.
- Make cancel/abort routing skip stale contexts rather than throwing.

## Verification

- `pnpm --dir /home/agent/forks/remote_pi/pi-extension install` if dependencies are absent.
- `pnpm --dir /home/agent/forks/remote_pi/pi-extension typecheck`
- `pnpm --dir /home/agent/forks/remote_pi/pi-extension test`
- `pnpm --dir /home/agent/forks/remote_pi/pi-extension build`
- Manual smoke: switch/load local package, reconnect a mobile app to a replaced/resumed Pi session,
  and confirm Pi does not crash.

## Implementation notes

- Files changed: `/home/agent/forks/remote_pi/pi-extension/src/index.ts`.
- Patch branch: `fix/stale-context-reconnect` pushed to `KevounC/remote_pi` at `f4a3743`.
- Implemented stale-safe helpers for `ctx.ui` access, notifications, cwd fallback, and late
  `pi.sendMessage()` calls; cleared captured contexts during `session_shutdown`; routed reconnect
  and known-peer message handling through the freshest `session_start` context where possible.
- Cancel/abort routing now skips only contexts that throw Pi's stale-context error; ordinary abort
  errors still surface as correlated app errors, preserving existing behavior.
- Tests added: none; existing coverage includes reconnect, cancel, send failure, and extension event
  paths.
- Verification: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` passed in
  `/home/agent/forks/remote_pi/pi-extension` (572 passed, 3 skipped).
- Manual smoke: after a live session resume, remote-pi reported `Mesh name: SNC` and `Relay connected`
  without the previous app-facing `internal_error`.
- Post-review private-carry follow-up: mobile messages were accepted and persisted but did not render
  visibly in the workstation Pi TUI. Fixed on the same private branch at `83d1fa5` by sending idle
  app-originated messages as normal `sendUserMessage(content)` calls and reserving `deliverAs: "steer"`
  for active/working turns; verification passed again.
- Discrepancies from design: source-fix was implemented directly after investigation instead of a
  separate later handoff because the crash source was isolated and the operator asked to continue.
- Adjacent issues parked: none.

## Acceptance

- Source changes in the fork implement the stale-context guard.
- Verification passes or any failures are classified as pre-existing vs introduced.
- A patch branch is pushed to `KevounC/remote_pi`.
- Upstream contribution path is decided: carry privately for now on `KevounC/remote_pi:fix/stale-context-reconnect`; defer upstream PR until the fix has more live soak time.

## Review (2026-06-27)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: Consider adding an exact stale-`ctx.ui` regression test before an upstream PR; acceptable to carry privately with the current full-suite pass and live smoke.

**Notes**: Substrate story review plus targeted standard code review of `/home/agent/forks/remote_pi` branch `fix/stale-context-reconnect`, commit `f4a3743`, file `pi-extension/src/index.ts`. Checked stale UI resolution (`_safeUi`/`_currentUi`/`_refreshFooter`), notify/send wrappers (`_notify`, `_sendPiMessage`, `_wakeAgent`, mesh message delivery), `session_shutdown` context clearing and reused-instance `session_start` rearm, reconnect routing through `_lastEventCtx`, and cancel behavior in `_abortCurrentTurn`. Ordinary abort errors still surface; stale-context aborts are skipped. Verification record is green: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` (572 passed, 3 skipped), with positive live reload/resume smoke. Parent remains active because sibling stories are still drafting.

## Post-review follow-up review (2026-06-27)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Reviewed private branch follow-up commit `83d1fa5` plus root note commit `f514f3a5`. The idle path now calls `sendUserMessage(content)` without a delivery mode, matching Pi's documented non-streaming behavior that normal user messages are sent immediately and rendered like typed prompts. Active/busy paths still pass `{ deliverAs: "steer" }` when the app explicitly requests steering or `room_meta.working` indicates an active turn, preserving stale-context active steering behavior. The echo contract remains unchanged except that idle echoes omit `streaming_behavior`, while steered echoes retain it. Verification record is green (`corepack pnpm typecheck && corepack pnpm test && corepack pnpm build`, 572 passed/3 skipped) and live smoke confirmed `Mobile test` rendered in the workstation Pi TUI after reload.
