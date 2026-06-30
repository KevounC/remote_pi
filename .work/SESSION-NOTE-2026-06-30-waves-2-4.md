# Session note — 2026-06-30 (cont) — bold-refactor autopilot drain in progress

Transient handoff note at `.work/` root (no frontmatter). Supersedes earlier
2026-06-30 session notes for current state. Delete when the bold-refactor
campaign completes. Per `.agents/rules/agent-discipline.md` this is NOT a
durable artifact — don't link durable docs at it.

## TL;DR — where the campaign stands now

Operator asked to clear pre-existing test failures before continuing the drain,
then keep draining. This session did both, then ran a continuous multi-wave
autopilot drain (Waves 5-8+, ~10 waves total).

**Stage counts: ~114 done / ~61 implementing / 6 drafting** (was 68 done /
92 implementing at session start — +46 done). 90+ commits this session.

**3 agents typically running, disjoint subprojects** (relay / pi-ext / cockpit /
app), each reviewed independently as it lands. Deeper verification on HIGH-risk
reducers + generated-contract stories; recurring false-failure pattern caught by
independent re-runs (see below).

## ⚠️ CRITICAL: pi-ext suite is FULLY GREEN (test debt cleared)

`9aa2c42` cleared 25 pre-existing pi-ext failures (19 extension.test.ts + 6
codec.test.ts) — all from the canonical-session attribution gate tightening,
NOT the drain. Full suite now **648 passed | 3 skipped | 0 failed (44 files)**;
typecheck clean. Baseline is ZERO failures.

## ⚠️ RECURRING FALSE-FAILURE PATTERN (filed, now consistently recognized by agents)

EIGHT pi-ext implement agents hit a false-failure pattern (reporting 1-66
"mesh/cwd-lock/UDS/`rename:<name>`/`name-assigned`/`supervisor.sock`/`after a
clean reset`" failures that do NOT exist when the orchestrator re-runs vitest).
The LAST THREE agents CORRECTLY recognized it as the known false-alarm signature
thanks to the enhanced briefing (which tells agents the pattern is confirmed,
gives the exact test-name signature, and says not to chase it). The orchestrator's
independent vitest re-run remains the reliable gate. Filed at
`.work/backlog/backlog-piext-agents-false-uds-failure-claims.md` (updated: cause
likely the subagent's execution environment, not a simple flake — 5th data point
showed "persistent across both runs"; structural fix may be needed beyond the
instructional mitigation that now works).

## Epics advanced to done this session (10 parent containers, all children done)
- `epic-bold-reachability-contract-state-machine` (4/4)
- `epic-bold-generated-protocol-schema-source` (5/5)
- `epic-bold-cockpit-workspace-projection-workspace-document` (6/6)
- `epic-bold-transcript-event-log-projection-derive` (6/6)
- `epic-bold-generated-protocol-rust-codegen` (5/5)
- `epic-bold-relay-typed-actor-control-handlers` (6/5)
- `epic-bold-cockpit-workspace-projection-agent-session` (5/5)
- `epic-bold-relay-typed-actor-frame-dispatch` (5/5)
- `epic-bold-split-pi-extension-index-owner-multiplexer-module` (5/5)
- `epic-bold-relay-typed-actor-registry-split` (5/5)

## Currently in flight
- `cli-daemon-pairing-step-6` (pi-ext, final step of that arc, HIGH-risk CLI
  bootstrap). No other agents running — relay/app/cockpit slots idle (no ready
  non-colliding stories: all ready stories are pi-ext, colliding with the running
  agent).

## Resume instructions
1. **1 agent in flight** (`cli-daemon-pairing-step-6`). Wait for completion,
   review (HIGH-risk CLI bootstrap + test-export preservation; full pi-ext suite
   green confirmation — re-run vitest independently, don't trust agent failure
   claims per the false-failure pattern).
2. After it lands, the pi-ext front frees for the next pi-ext writer. Ready
   pi-ext stories: `composition-root-step-4`, `sdk-session-projection-step-2`,
   `transcript-event-log-store-step-3` (pi-ext), `cockpit-control-rpc-step-2`
   (pi-ext files despite epic name), `late-attach-step-4` (cross-cutting app+pi-ext).
   Serialize ONE pi-ext writer per wave.
3. Newly-unblocked arcs ready to dispatch when slots free:
   - `relay-transport-module` arc (step-1..5) — blocked on `composition-root`
     epic (not done; step-4 is the next pi-ext writer). Once composition-root
     lands, this relay arc unblocks.
   - `generated-protocol-ts-codegen` arc (step-1..5, dep schema-source done) —
     pi-ext (TS codegen).
   - `transcript-event-log-store` steps 4-5 (app+pi-ext, blocked on step-3 pi-ext).
   - `transcript-event-log-hydration-replay` arc (app, blocked on
     transcript-event-log-store epic — needs steps 3-5).
   - `cockpit-control-rpc` steps 2-3 (step-2 is pi-ext, step-3 follows).
4. Collision constraints (unchanged): relay `rooms.rs`/`registry.rs`/`peer.rs`
   cluster (one relay writer per wave — but relay arcs are mostly done now);
   pi-ext `index.ts` god-file (one pi-ext writer per wave); app/cockpit free
   unless an arc runs there.
5. Generated-contract invariant: any story touching `relay/src/protocol/generated/*`
   or `app/lib/protocol/generated/*` MUST change the generator, regenerate,
   confirm clean regen-diff (run twice for determinism). Never hand-edit.
6. Reviews: fast-lane for stories (green verification + ownership + read code →
   advance review→done). HIGH-risk + generated-contract stories get deeper
   verification. Orchestrator independently re-runs tests for pi-ext (false-
   failure pattern).

## Dev environment incantations (unchanged, still load-bearing)
- **Flutter**: `~/projects/remote_pi/.tools/flutter/bin/flutter` (not on PATH).
  `/opt/flutter` is GONE (the prior session's read-only `/opt/flutter/bin/cache`
  blocker is resolved — this cleared the 3x-bounced transcript-event-log-store-1).
- **Pub cache**: `PUB_CACHE=~/projects/remote_pi/.pub-cache` (default READ-ONLY).
  `app/` pub get online OK; `cockpit/` pub get `--offline` REQUIRED.
- **pi-extension pnpm**: `export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`.
- **relay cargo**: clean. `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
- **relay generated-contract regen-check**: from `protocol/`:
  `node --import tsx scripts/list-types.ts | node ../tools/protocol-codegen/bin/protocol-codegen.mjs --target rust --schema - --out-dir ../relay/src/protocol/generated --check`
  + determinism double-run + diff vs committed.
- **node codegen**: `node tools/protocol-codegen/bin/protocol-codegen.mjs` (v24.18.0).

## Coordination rule (unchanged)
Do NOT `git add`/`git commit` while parallel write-subagents are in flight —
agents commit their own work; orchestrator commits only notes/docs/review-advances
when no agents are writing to those paths. Stage explicitly (never `-A`/`.`).
`*.key`/`*.pem` are untracked local secrets — NEVER commit.
