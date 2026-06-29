---
id: story-remote-pi-stale-context-investigation
kind: story
stage: done
tags: [pi-extension, bug]
parent: feature-remote-pi-fork-vendor-and-mobile-surface
depends_on: []
release_binding: extension-0.5.4
gate_origin: null
created: 2026-06-27
updated: 2026-06-27
---

# Investigate remote-pi stale-context rejection during session replacement

## Brief

Investigate the recurring `remote-pi` failure that reaches the mobile/client surface as:

```text
internal_error: Agent rejected incoming message: This extension ctx is stale after session replacement or reload.
```

The immediate operator workaround is to continue from code-server, but the investigation should pin
which `remote-pi` path still uses a stale Pi extension context after `/reload`, `newSession`,
`fork`, `switchSession`, or session resume/replacement. The output feeds
[`story-remote-pi-stale-context-source-fix`](story-remote-pi-stale-context-source-fix.md) rather than
landing a speculative patch first.

## Grounding

Pi's extension API contract is explicit: after `ctx.newSession()`, `ctx.fork()`, or
`ctx.switchSession()`, post-replacement work must move into `withSession` and use the replacement
context passed there; after `await ctx.reload()`, handlers should treat reload as terminal and avoid
using the old context. Captured `pi`, command `ctx`, `ctx.sessionManager`, `ctx.ui`, or other
session-bound objects can throw once the old runtime is torn down.

Known source areas to inspect in `/home/agent/forks/remote_pi/pi-extension/src/index.ts`:

- `_refreshFooter()` and all callers that omit an explicit fresh context.
- `_attachOwner()` / relay `onMsg` paths that run when a mobile owner reconnects.
- `session_start` / `session_shutdown` state reset and any retained `_lastCtx`, `_lastEventCtx`, or
  `_pi` references.
- `session_new` / fork / resume handling around `withSession` and follow-up mobile sync.
- late `pi.sendMessage` / `pi.sendUserMessage` calls that can run after session replacement.
- cancellation/abort routing that may retain the command context from the replaced session.

## Observed trigger

- 2026-06-27 operator recollection: the failure likely happened after leaving a Pi/remote-pi session
  stale for a few minutes, then picking it back up from the mobile/client surface. That points the
  investigation toward idle/reconnect/sync callbacks that outlive the original session context, not
  only explicit `/reload` or manual session-switch commands.

## Investigation plan

1. Capture the current failing sequence from the operator path: idle/stale session interval,
   mobile reconnect/pair/sync message, any implicit session replacement/reload action, and the first
   stack frame that throws.
2. Compare the sequence against Pi docs for session replacement and reload lifecycle.
3. Audit all `remote-pi` module-level context captures and context-less helper calls; classify each
   as safe data, stale-risk session-bound object, or intentionally replacement-safe.
4. Produce a minimal patch plan for the source-fix story, including any targeted tests or manual
   smoke steps needed to prove the crash is gone.
5. If the failure is broader than one source fix, split follow-up work before patching.

## Preliminary audit notes

- The remembered trigger (idle for a few minutes, then resume from the app) matches the reconnect
  path in `pi-extension/src/index.ts`: relay/app traffic reaches `_installAutoListener()`, known
  peers without an active channel call `_attachOwner()`, and `_attachOwner()` immediately calls
  `_refreshFooter()` with no explicit context.
- Current `_refreshFooter()` falls back to module-level `_lastCtx` and reads `target.ui` before any
  stale-context guard. If `_lastCtx` belongs to a command/session that Pi has replaced, that property
  access itself can throw, matching the observed stack: `_refreshFooter` → `_attachOwner` → relay
  `onMsg`.
- The same idle/reconnect path also uses `_lastCtx?.ui.notify(...)` in `_attachOwner()` and
  `_onPeerDisconnect()`, and `_wakeAgent()` uses `_lastCtx?.ui.notify(...)` when `sendUserMessage`
  throws. Those are secondary stale-context candidates after the footer crash is guarded.
- `session_start` refreshes `_lastEventCtx`, but it does not refresh command-capable `_lastCtx` for
  external replacement flows. `session_shutdown` tears down relay state but does not clear `_lastCtx`,
  so old command contexts can remain reachable by late timers/relay callbacks.
- 2026-06-27 live resume signal after applying the source guard: the remote-pi surface reported
  `Mesh name: SNC` and `Relay connected` after a session resume/reconnect rather than surfacing the
  previous `internal_error`. Treat this as a positive smoke signal, not full acceptance, until the
  source-fix verification and a deliberate idle/reconnect manual smoke complete.

## Implementation notes

- Best-known trigger recorded: idle/stale mobile session for a few minutes, then resume/reconnect.
- Candidate sites classified: `_refreshFooter()` fallback to `_lastCtx`, `_attachOwner()` reconnect
  notifications, `_onPeerDisconnect()` notifications, late `_pi.sendMessage()`/`sendUserMessage()`
  error paths, `_lastCtx` cwd access, and cancel/abort fallback contexts.
- Patch prepared and pushed in `/home/agent/forks/remote_pi` branch
  `fix/stale-context-reconnect` at `f4a3743`.
- Verification: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` passed in
  `/home/agent/forks/remote_pi/pi-extension` (572 passed, 3 skipped).
- Adjacent issues parked: none.

## Acceptance

- The exact reproduction path or best-known trigger is recorded in this item or the source-fix item.
- Stale-context candidate sites in `pi-extension/src/index.ts` are classified with enough detail to
  patch deliberately.
- The source-fix story has a concrete implementation plan and verification checklist update.
- Any additional failure class discovered during investigation is parked/scoped separately instead of
  being silently folded into the patch.

## Review (2026-06-27)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Substrate story review with targeted code cross-check against `/home/agent/forks/remote_pi` commit `f4a3743`. The item coherently records the best-known idle/resume trigger, the stale `_lastCtx`/`ctx.ui` failure path (`_refreshFooter` → `_attachOwner` → relay `onMsg`), secondary notification/send/cancel candidates, and the handoff into the source-fix story. No additional failure class needed a separate item.
