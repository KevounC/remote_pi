---
id: backlog-piext-extension-test-19-failures
created: 2026-06-30
updated: 2026-06-30
tags: [test-debt, pi-extension, bug, pre-existing]
---

# pi-extension extension.test.ts: 19 pre-existing failures (relay-mock-not-fired)

## Symptom

`cd pi-extension && corepack pnpm exec vitest run src/extension.test.ts` reports
**19 failed | 128 passed (147)** at HEAD (after the 2026-06-30 fixture-count
fix). All 19 share the same failure shape: an expected relay `send` mock call
never happened — `AssertionError: expected [] to have a length of 1 but got +0`.

## Cluster (by describe block)

- `multi-channel broadcast (W2D)` — 13 failures (session_sync, user_message
  rebroadcast, queued_message set/clear/drain, plan/30 image echo, plan/43
  steering x4, rebroadcast-before-agent, app session_new recapture, app prompt
  async rejection)
- `routeClientMessage cancel handling` — 4 (cancel uses freshest ctx, cancel
  before pi binding guard, cancel no abort ctx, abort throw + later ping)
- `session_shutdown teardown` — 1 (app user_message after shutdown)
- `session sync` — 1 (session_sync no active session)

## Evidence this is PRE-EXISTING (not introduced by the bold-refactor drain)

- The sandbox-UDS-EPERM ceiling (now lifted) previously masked these as env
  failures. With UDS working, 127/147 pass and the 19 are now visible as real
  failures.
- Reverting the 4 pi-ext commits landed this session (turn-state-algebraic-3,
  transcript-projection-derive-4, reachability-pi-adapter-3, reachability-pi-adapter-4)
  produced **32 failures** at the pre-session baseline — i.e. this session's
  work *reduced* failures by 12 (the transcript-projection agent's session_id
  routing fixed 12). So the 19 are not caused by the drain; they predate it.
- The transcript-projection-derive-step-4 agent's notes record that adding
  `session_id` to the test fixtures' session-scoped `session_sync`/`user_message`
  routing fixed 12 pre-existing `session_mismatch` failures — strong signal
  that the remaining 19 may share a related root cause (canonical-session
  attribution gating that the test fixtures don't yet satisfy).

## Likely root cause (hypothesis, needs confirmation)

The canonical-session work (wire-discriminator, identity-model, app-attribution-
hydration) tightened session attribution: inbound frames without a matching
`session_id` are now dropped/gated. The 19 failing tests' fixtures likely send
frames that hit the new session gate and get dropped before the relay mock sees
the outbound `cancelled`/`session_history`/`queued_message`/echo. The
transcript-projection-derive-step-4 fix (routing session-scoped fixtures with
the current `session_id`) confirms this pattern.

## Triage next step

Pick ONE failing test (e.g. `cancel uses freshest session_start ctx`), trace
whether the inbound `cancel` frame is being dropped by the session gate before
the router emits `cancelled`. If so, the fix is test-fixture alignment (route
through the canonical session like step-4 did), NOT a product change. If the
frame reaches the router but the router doesn't emit, that's a real product bug
— file it separately.

## Why parked, not fixed inline

Pre-existing test debt outside any active bold-refactor story's scope. The
autopilot drain's job is the substrate stories, not chasing pre-existing suite
red. Once the canonical-session epic is fully landed, these may resolve
naturally as the session-attribution model stabilizes; re-run then.

## Reproduce

```bash
cd pi-extension
export PNPM_HOME=~/projects/remote_pi/.pnpm-store npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache
corepack pnpm exec vitest run src/extension.test.ts --reporter=dot
# expect: 19 failed | 128 passed (147)
```
