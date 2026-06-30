# Session note — 2026-06-30 (cont) — bold-refactor autopilot drain in progress

Transient handoff note at `.work/` root (no frontmatter). Supersedes earlier
2026-06-30 session notes for current state. Delete when the bold-refactor
campaign completes. Per `.agents/rules/agent-discipline.md` this is NOT a
durable artifact — don't link durable docs at it.

## TL;DR — where the campaign stands now

Operator asked to clear pre-existing test failures before continuing the drain,
then keep draining. This session did both, then ran a continuous multi-wave
autopilot drain (Waves 5-8+).

**Stage counts: 100 done / 72 implementing / 1 review / 6 drafting** (was
68 done / 92 implementing at session start — +32 done). 59 commits this session.

**3 agents always running, disjoint subprojects** (relay / pi-ext / cockpit / app),
each reviewed independently as it lands. Deeper verification on HIGH-risk reducers
+ generated-contract stories; recurring false-failure pattern caught by
independent re-runs (see below).

## ⚠️ CRITICAL: pi-ext suite is FULLY GREEN (test debt cleared)

`9aa2c42` cleared 25 pre-existing pi-ext failures (19 extension.test.ts + 6
codec.test.ts) — all from the canonical-session attribution gate tightening,
NOT the drain. Full suite now **642 passed | 3 skipped | 0 failed (43 files)**;
typecheck clean. Wave 5+ pi-ext agents can require full `extension.test.ts`
green — baseline is ZERO failures.

## ⚠️ RECURRING FALSE-FAILURE PATTERN (filed for investigation)

FOUR consecutive pi-ext implement agents (openai-codex/gpt-5.5, high thinking)
falsely reported "4-33 UDS/mesh/cwd-lock/broker.sock failures" that do NOT exist
when the orchestrator re-runs the suite (always 642/645, 0 failures). The
agents appear to hit a transient state (own mid-write files during the run,
parallel-agent working-tree interference, or stale vitest cache) and
mis-attribute it to the (now-lifted) UDS ceiling. Filed at
`.work/backlog/backlog-piext-agents-false-uds-failure-claims.md`. The
orchestrator's independent re-run is the gate; do NOT trust agent failure
claims for pi-ext without re-running. Enhanced briefings (re-run 2-3x) did not
fully eliminate it.

## Epics advanced to done this session (parent containers, all children done)
- `epic-bold-reachability-contract-state-machine` (4/4)
- `epic-bold-generated-protocol-schema-source` (5/5)
- `epic-bold-cockpit-workspace-projection-workspace-document` (6/6)
- `epic-bold-transcript-event-log-projection-derive` (6/6)
- `epic-bold-generated-protocol-rust-codegen` (5/5)
- `epic-bold-relay-typed-actor-control-handlers` (6/6)

## Waves landed this session (each story verified + reviewed + done)

**Wave 5 (5/5):** dart-codegen-5, app-attribution-hydration-4 (HIGH-risk reducer),
workspace-document-6, transcript-projection-5, rust-codegen-3 (generated-contract).

**Wave 6 (4/4):** reachability-app-adapter-3, projection-consumers-3 (HIGH-risk
convergence), transcript-projection-6 (pi-ext deferred), late-attach-3.

**Wave 7 (7/7):** rust-codegen-4, projection-consumers-4, identity-model-5
(HIGH-risk re-key), control-handlers-5, agent-session-1, owner-multiplexer-2
(HIGH-risk), rust-codegen-5.

**Wave 8 (in progress, 9/11 done + 3 running):** control-handlers-6,
agent-session-2, cli-daemon-pairing-3, agent-session-3 (HIGH-risk process/turn
split), frame-dispatch-1/2/3/4, agent-session-4, owner-multiplexer-3 (HIGH-risk
ingress). Running: frame-dispatch-5 (HIGH-risk final switch-over),
owner-multiplexer-4, agent-session-5 (final UI migration).

## Dev environment incantations (unchanged, still load-bearing)
- **Flutter**: `~/projects/remote_pi/.tools/flutter/bin/flutter` (not on PATH).
- **Pub cache**: `PUB_CACHE=~/projects/remote_pi/.pub-cache` (default READ-ONLY).
  `app/` pub get online OK; `cockpit/` pub get `--offline` REQUIRED.
- **pi-extension pnpm**: `export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`.
- **relay cargo**: clean. `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
- **relay generated-contract regen-check**: from `protocol/`:
  `node --import tsx scripts/list-types.ts | node ../tools/protocol-codegen/bin/protocol-codegen.mjs --target rust --schema - --out-dir ../relay/src/protocol/generated --check`
  + determinism double-run (two temp dirs, `diff -r` empty) + diff vs committed
  (empty = no hand-edits). Any story touching `relay/src/protocol/generated/*`
  MUST change the generator, regenerate, confirm clean regen-diff. NEVER hand-edit
  generated files.
- **node codegen**: `node tools/protocol-codegen/bin/protocol-codegen.mjs` (v24.18.0).

## Coordination rule (unchanged)
Do NOT `git add`/`git commit` while parallel write-subagents are in flight — agents
commit their own work; orchestrator commits only notes/docs/review-advances when
no agents are writing to those paths. Stage explicitly (never `-A`/`.`).
`*.key`/`*.pem` are untracked local secrets — NEVER commit.

## Resume instructions
1. **3 Wave-8 agents in flight** (frame-dispatch-5 relay, owner-multiplexer-4
   pi-ext, agent-session-5 cockpit). Wait for completions, review-pass each
   (deeper verify frame-dispatch-5 HIGH-risk final switch-over + owner-multiplexer
   HIGH-risk). The pi-ext suite is a clean baseline — re-run independently, do
   NOT trust agent failure claims (false-failure pattern).
2. After Wave 8 clears, the remaining active arcs:
   - **relay frame-dispatch**: step-5 is the LAST step; then `relay-typed-actor-
     registry-split` arc (step-1..5) unblocks (dep: frame-dispatch + control-
     handlers epics, both done).
   - **pi-ext index.ts split**: composition-root-step-4, sdk-session-projection-2,
     late-attach-step-4 (cross-cutting app tests), cli-daemon-pairing-step-4/5/6,
     owner-multiplexer-step-5, + relay-transport-module arc — serialize ONE pi-ext
     writer per wave (all share index.ts/extension.test.ts).
   - **cockpit agent-session**: step-5 is the LAST step; arc then complete.
   - **generated-protocol-cockpit-control-rpc** arc (step-1..3, dep schema-source
     done) and **generated-protocol-ts-codegen** arc (step-1..5, dep schema-source
     done) — both newly unblocked, ready to dispatch.
   - **transcript-event-log-store** + **transcript-event-log-hydration-replay**
     arcs (dep transcript-projection-derive epic done) — newly unblocked.
3. Collision constraints: relay `rooms.rs`/`registry.rs`/`peer.rs` cluster (one
   relay writer per wave); pi-ext `index.ts` god-file (one pi-ext writer per wave);
   app/cockpit generally free unless an arc is running there.
4. Generated-contract invariant applies to any story touching
   `relay/src/protocol/generated/*` or `app/lib/protocol/generated/*`.
5. Reviews: fast-lane for stories (green verification + ownership + read code →
   advance review→done). HIGH-risk + generated-contract stories get deeper
   verification of the specific invariant. Orchestrator independently re-runs
   tests for pi-ext (false-failure pattern).
