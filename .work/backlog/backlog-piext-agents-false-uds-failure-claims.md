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
