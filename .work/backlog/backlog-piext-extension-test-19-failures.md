---
id: backlog-piext-extension-test-19-failures
created: 2026-06-30
updated: 2026-06-30
resolved: 2026-06-30
resolution_commit: 9aa2c42
tags: [test-debt, pi-extension, bug, pre-existing, resolved]
---

# pi-extension extension.test.ts: 19 pre-existing failures (relay-mock-not-fired)

## Status: RESOLVED (2026-06-30, commit 9aa2c42)

Cleared alongside a related 6-failure drift in `codec.test.ts` (same
canonical-session attribution family). Full pi-ext suite now green:
`corepack pnpm typecheck` clean; `vitest run` 640 passed | 3 skipped | 0
failed across 43 files.

## Original symptom (kept for the record)

`cd pi-extension && corepack pnpm exec vitest run src/extension.test.ts`
reported **19 failed | 128 passed (147)**. All 19 shared one root cause:
the canonical-session gate (added 2026-06-29 in `identity-model-step-3`)
requires a matching `session_id` on every session-scoped client frame.
The failing tests predated the gate and emitted those frames without
`session_id`, so the gate correctly rejected them as `session_mismatch`
before the router emitted the expected `cancelled`/`session_history`/
`queued_message`/echo.

## Root cause confirmed by fix

Test-debt, NOT a product bug. The gate's behavior is correct (and is
itself well-tested by `session_gate.test.ts`). The fix applied the
proven convention `transcript-projection-derive-step-4` already used on
12 sibling tests: route the test fixtures through the captured canonical
session id.

### Three nuances the fix handled

1. **session_start re-captures the session id.** When the session_start
   ctx carries no `sessionManager`, `_captureRemoteSession` generates a
   fresh uuid7 — different from the `pair_ok` id. So the cancel cluster
   reads the live id via `_getRemoteSessionIdForTest()` after
   `onSessionStart`, not `currentSessionIdFromSends()`.
2. **session_new swaps the session id.** The post-new `user_message`
   carries the freshly-captured id (`_getRemoteSessionIdForTest()`),
   not the pre-new one.
3. **post-shutdown user_message** (test #19): pin the session id via
   `_setRemoteSessionIdForTest` so the frame passes the gate and reaches
   the `_disposed` guard the test actually targets — which returns
   `internal_error` exactly as the original assertion expected,
   preserving the test's intent (no stale-pi call, no leak).

Also: empty `queued_message_state` now stamps `session_id` (correct
canonical-session behavior); assertions relaxed from strict `toEqual` to
`toMatchObject({ type })` + `not.toHaveProperty("id"|"text")` to capture
the "empty state" semantic without forbidding the legitimate stamp.

## Related: codec.test.ts (6 failures, same family)

The canonical-session work added `action_ok`/`action_error`/`compaction`/
`models_list`/`queued_message_state` as server types and added fixtures
for them, but `codec.test.ts`'s hand-maintained `SERVER_TYPE_FILES` set
and its `31 fixture files present` count never updated. Fixed in the same
commit by deriving the server-fixture set from the `session_scope`
registry (single source of truth) so it can't drift again; `agent_stream`
kept as the only filename alias.

## Why this mattered for the drain

Wave 5 includes HIGH-risk convergence stories (late-attach,
projection-consumers) in the session-attribution area. The "no new
failures beyond 19" check only works if agents diff the failing-name set,
not the count — and the heterogeneous shapes made count-based checking a
real masking risk. A clean suite makes Wave 5 verification trivial and
trustworthy.
