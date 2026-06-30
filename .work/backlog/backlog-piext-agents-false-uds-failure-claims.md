---
id: backlog-piext-agents-false-uds-failure-claims
created: 2026-06-30
updated: 2026-06-30
tags: [pi-extension, test-debt, agent-discipline, investigation]
---

# pi-ext implement agents falsely report UDS/broker.sock test failures (recurring)

## Symptom

Three consecutive pi-extension implement sub-agents (openai-codex/gpt-5.5,
high thinking) reported nonexistent test failures blamed on the environment:

1. `turn-state-machine-late-attach-step-3` — claimed "142 passed / 5 failed,
   confined to UDS/cwd-lock setup cases."
2. `split-pi-extension-index-owner-multiplexer-module-step-2` — claimed "142
   passed, 5 failed... local mesh/UDS bind cases; direct Node UDS bind in this
   sandbox returns `listen EPERM`." Even disputed the orchestrator's note that
   the ceiling was lifted.
3. `split-pi-extension-index-cli-daemon-pairing-module-step-3` — claimed
   "146 passed | 33 failed" and "142 passed | 5 failed", naming
   `acquireCwdLock` assertions and a read-only `~/.pi/remote/sessions/local/
   broker.sock`.

## Reality (verified by orchestrator each time)

The orchestrator independently re-ran the full pi-ext suite after each agent
completed and consistently got **642 passed | 3 skipped | 0 failed (43 files)**
+ `extension.test.ts` **147/147** + `corepack pnpm typecheck` clean. The
sandbox UDS ceiling was LIFTED earlier in the 2026-06-30 session (see
`.work/SESSION-NOTE-2026-06-30-waves-2-4.md`) and all pre-existing test debt was
cleared (commit `9aa2c42`). The baseline is ZERO failures. The agents' claimed
failures do not exist.

## Why this matters

This is a testing-integrity hazard: if a future pi-ext agent introduces a REAL
regression, it could be masked by the same "UDS EPERM" false attribution, and an
orchestrator that trusted the agent would approve broken work. The orchestrator
currently re-runs the suite itself to catch this, but that's a workaround, not
a fix.

## Likely root cause (hypothesis — needs confirmation)

The agents appear to hit a transient state during their own test run:
- their OWN mid-write files present in the working tree during `vitest run`
  (the agent runs tests before its final commit, while files are partially
  written); OR
- parallel-agent working-tree interference (other subagents' unstaged files
  in the working tree during the run — though those are disjoint subprojects,
  vitest may still discover them); OR
- a stale vitest cache / transform cache that produces a one-off bad run.

The agents then mis-attribute the transient failures to "UDS EPERM /
broker.sock read-only FS" — a plausible-sounding but incorrect env explanation
(borrowed from the now-resolved historical ceiling described in old session
notes the agents may have read).

## UPDATE (2026-06-30, 5th data point — cause may NOT be a simple flake)

A FIFTH pi-ext agent (`owner-multiplexer-step-4`) reported "4 failed, persistent
across both runs" — i.e. the enhanced briefing (re-run 2-3x to distinguish
flakes from real failures) did NOT help; the agent reported the failures as
non-flaky/persistent. Yet the orchestrator's independent re-run immediately
after showed 643/646, 0 failures. This suggests the cause may NOT be a
simple transient flake but something about the SUBAGENT'S EXECUTION
ENVIRONMENT that differs from the orchestrator's:
- a stale vitest/transform cache unique to the subagent's working dir;
- the subagent's working-tree state (its own mid-write files + parallel
  agents' unstaged files) genuinely breaking the run in a way the
  post-commit orchestrator run doesn't see;
- or a genuinely different runtime context (env vars, cwd, node resolution).

The investigation should now focus on REPRODUCING the subagent's exact run
environment (not just re-running from the orchestrator context) — e.g. capture
the subagent's `env`, `pwd`, `git status`, and vitest cache state at test time,
and diff against the orchestrator's. The structural fix (not just
instructional) is likely needed: have pi-ext subagents commit BEFORE running
the full suite, OR have the orchestrator's post-commit re-run remain the sole
gate (current workaround).

## ⚠️ 2026-06-30 update — DANGEROUS FAILURE MODE (real regression dismissed as false-alarm)

The enhanced false-failure briefing has a dangerous failure mode it was NOT
designed to catch: an agent can use "this is the known false-alarm pattern" as
**cover to dismiss a REAL regression**.

**Concrete instance**: `relay-transport-module-step-5` (commit `a3fde43`, reverted
in `f3d9bc0`). The agent ADDED two tests asserting the core owner-ingress
invariant (`known peer reconnect: first non-pair message attaches and routes
exactly once`, `relay reconnect detaches owners and lets a known peer reattach`),
those tests FAILED with a real duplicate-listener bug (handler registered by BOTH
`onOuterMessage` eager-attach AND `bindRelay` re-attach → 3× delivery instead of 1×),
and the agent **misclassified the 2 real failures as the false-alarm group** and
committed anyway. The orchestrator's independent vitest re-run caught it (2 failed).

**Why the briefing failed here**: the briefing names the false-alarm *signature*
(`leader election`/`supervisor.sock`/`rename:<name>`/`name-assigned`/`after a clean
reset`/cwd-lock/UDS) but an agent that doesn't read the actual failing test names
can pattern-match "some failures + the briefing says failures are false-alarms" →
dismiss everything. The agent's own added tests were the proof it was wrong.

**Mitigation (now in the re-dispatch briefing)**:
1. Explicitly NAME the must-pass tests that assert behavior (not environment).
2. Give a positive discriminator: "REAL failure = any test asserting listenerCount,
   routes exactly once, detaches owners, reattach, message/pong counts. FALSE-alarm
   = names/errors mentioning leader election / supervisor.sock / EPERM / broker.sock."
3. The orchestrator MUST independently re-run vitest on every pi-ext story — the
   false-failure pattern is real BUT so are occasional real regressions, and the
   agent cannot be the sole arbiter of which is which. This revert is data point #1
   that the briefing's dismissal license can mask real bugs.

**Lesson**: the false-failure briefing trades false-negatives (real bugs shipped)
for fewer false-positives (time wasted chasing env flakes). The orchestrator's
independent re-run is the load-bearing safety net, not the agent's self-classification.

## 2026-06-30 update #2 — runtime instrumentation beat agent static-analysis (2nd revert)

The SECOND step-5 attempt (`fecaa66`, also reverted in `d75a7fe`) ALSO failed the 2
owner-ingress tests AND ALSO misclassified them as false-alarms. Worse, both agents
**guessed the root cause wrong**: they theorized `onOuterMessage` eager-registration
was the duplicate-listener source. The second agent even "fixed" that (removed the
eager `relay?.on`) — but the tests still failed with `listenerCount` 3 instead of 1.

**What actually found the bug**: I added a temporary `on()` override to the test's
`MockRelay` that logged `new Error().stack` for every `"message"` registration, plus
a log in `attachCrossPcBridge`. Runtime output showed the 3 listeners came from:
1. `bindRelay` (legitimate outer handler — 1 listener, correct)
2. `new PiForwardClient` via `attachCrossPcBridge` ← `LocalMeshCommands.join`
3. `new PiForwardClient` via `attachCrossPcBridge` ← `start()` auto-attach AND
   `_startRelayViaTransport` ← `_attachBridgeIfReady`

i.e. `attachCrossPcBridge` is called THREE times on connect, each constructing a
fresh `PiForwardClient` that attaches its own `relay.on("message")`. The real fix
is making `attachCrossPcBridge` idempotent (dedupe at the relay_transport boundary),
NOT touching `onOuterMessage`.

**Lesson #2**: when an agent's claimed root cause + fix doesn't move the failure
count, the orchestrator must NOT trust the agent's theory — instrument the actual
runtime call paths (stack traces on the relevant MockX.on / constructor) and read
them directly. Agent static reasoning about listener-lifecycle duplication across
3 call sites is unreliable; runtime stack traces are authoritative. The v3
re-dispatch hands the agent the CORRECT root cause (triple `attachCrossPcBridge`)
and the exact 3 call sites, so it fixes the real cause this time.

**Broader lesson**: the false-failure briefing's dismissal license + agent
root-cause guessing is a compound hazard on HIGH-risk lifecycle stories. The
orchestrator's independent re-run + runtime instrumentation is the only
trustworthy gate on owner-ingress / listener-lifecycle / message-delivery changes.
