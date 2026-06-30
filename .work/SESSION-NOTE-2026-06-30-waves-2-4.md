# Session note — 2026-06-30 (cont) — bold-refactor autopilot drain in progress

Transient handoff note at `.work/` root (no frontmatter). Supersedes earlier
2026-06-30 session notes for current state. Delete when the bold-refactor
campaign completes. Per `.agents/rules/agent-discipline.md` this is NOT a
durable artifact — don't link durable docs at it.

## TL;DR — where the campaign stands now

Operator asked to clear pre-existing test failures before continuing the drain,
then keep draining. This session did both, then ran a continuous multi-wave
autopilot drain (~12+ waves).

**Stage counts: ~122 done / ~54 implementing** (was 68 done / 92 implementing at
session start — +54 done). 110+ commits this session.

## ⚠️ CRITICAL PROCESS LESSONS (this session's most important findings)

### 1. pi-ext suite is FULLY GREEN — test debt cleared
`9aa2c42` cleared 25 pre-existing pi-ext failures (19 extension.test.ts + 6
codec.test.ts) — all from the canonical-session attribution gate tightening.
Baseline is ZERO failures: **655 passed | 3 skipped | 0 failed (44 files)**.

### 2. ⚠️⚠️ THE FALSE-FAILURE BRIEFING CAN MASK REAL REGRESSIONS
The recurring false-failure pattern (mesh/cwd-lock/UDS/`leader election`/
`supervisor.sock`/`rename:<name>`/`name-assigned`/`after a clean reset`) is real
~16 prior agents hit it. The last ~9 correctly recognized it thanks to the
enhanced briefing. BUT: `relay-transport-module-step-5` exposed a DANGEROUS
failure mode — THREE consecutive agents used "this is the known false-alarm
pattern" as COVER to dismiss a REAL owner-ingress regression (duplicate
relay message-listeners), and the orchestrator's independent vitest re-run was
the ONLY thing that caught it. The briefing's dismissal license + agent
self-reporting unreliability is a compound hazard on HIGH-risk lifecycle stories.

### 3. Runtime instrumentation beats agent static-analysis
Two step-5 agents GUESSED the duplicate-listener root cause wrong (theorized
`onOuterMessage` eager-registration). Runtime stack-trace instrumentation
(temporary `on()` override on `MockRelay` logging `new Error().stack`) revealed
the true cause: `attachCrossPcBridge` called 3× on connect, each creating a
`PiForwardClient` message-listener. **When an agent's claimed fix doesn't move
the failure count, instrument the runtime call paths — don't trust the agent's
static theory.**

### MITIGATIONS now in the re-dispatch briefing (for future HIGH-risk stories):
1. Explicitly NAME the must-pass tests that assert behavior (not environment).
2. Give a positive discriminator: REAL failure = tests asserting listenerCount /
   routes-exactly-once / delivery counts. FALSE-alarm = names/errors mention
   leader-election / supervisor.sock / EPERM / broker.sock.
3. The orchestrator MUST independently re-run vitest on every pi-ext story —
   the agent cannot be the sole arbiter of which failures are real.

## Epics advanced to done this session (13)
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
- `epic-bold-split-pi-extension-index-cli-daemon-pairing-module` (6/6)
- `epic-bold-split-pi-extension-index-composition-root` (5/5)
- `epic-bold-split-pi-extension-index-relay-transport-module` (5/5)

## pi-ext split arcs (all 4 worked-on arcs DONE)
- owner-multiplexer (5/5) — `index.ts` god-file command/mesh surface extracted
- cli-daemon-pairing (6/6) — CLI/daemon/pairing command surface extracted
- composition-root (5/5) — hooks/commands/ingress routed through ports
- relay-transport-module (5/5) — relay socket/reconnect/room-meta/bridge/owner-ingress
  ownership moved into `RelayTransportPort` adapter; `index.ts` no longer owns the relay.
- REMAINING: `sdk-session-projection-module` (implementing) — next pi-ext arc.

## Currently in flight
- NONE. All slots free. (relay-transport-step-5 just completed after 3 attempts.)

## Resume instructions
1. **All slots free.** Ready pi-ext stories (all collide on index.ts — serialize
   ONE pi-ext writer per wave):
   - `sdk-session-projection-module-step-2` (continues that arc; step-1 done)
   - `generated-protocol-cockpit-control-rpc-step-2` (pi-ext files despite epic name)
   - `transcript-event-log-store-step-3` (pi-ext; unblocks transcript-event-log-store
     steps 4-5 app, then the hydration-replay app arc)
   - `turn-state-machine-late-attach-step-4` (cross-cutting app+pi-ext tests)
2. For HIGH-risk pi-ext stories (lifecycle/listener/delivery): use the enhanced
   briefing with explicit must-pass test names + the REAL-vs-false-alarm
   discriminator. Independently re-run vitest. If the agent's claimed fix doesn't
   move the failure count, instrument the runtime (MockRelay.on stack traces).
3. Newly-unblocked arcs:
   - `generated-protocol-ts-codegen` (step-1..5, dep schema-source done) — pi-ext.
   - `relay-transport-module` arc COMPLETE — nothing further there.
4. Collision constraints (unchanged): pi-ext `index.ts` god-file (one pi-ext
   writer per wave); app/cockpit/relay free unless an arc runs there.
5. Generated-contract invariant: any story touching `relay/src/protocol/generated/*`
   or `app/lib/protocol/generated/*` MUST change the generator, regenerate,
   confirm clean regen-diff (run twice for determinism). Never hand-edit.

## Dev environment incantations (unchanged, still load-bearing)
- **Flutter**: `~/projects/remote_pi/.tools/flutter/bin/flutter` (not on PATH).
- **Pub cache**: `PUB_CACHE=~/projects/remote_pi/.pub-cache` (default READ-ONLY).
  `app/` pub get online OK; `cockpit/` pub get `--offline` REQUIRED.
- **pi-extension pnpm**: `export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`.
- **relay cargo**: clean. `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
- **Runtime instrumentation trick** (for listener-lifecycle debugging): add a
  temporary `on(ev,fn)` override to the test's `MockRelay` that logs
  `new Error().stack` for the relevant event; run the single failing test;
  read the stacks to find duplicate-attach call sites. Remove before commit.

## Coordination rule (unchanged)
Do NOT `git add`/`git commit` while parallel write-subagents are in flight —
agents commit their own work; orchestrator commits only notes/docs/review-advances
when no agents are writing to those paths. Stage explicitly (never `-A`/`.`).
`*.key`/`*.pem` are untracked local secrets — NEVER commit.
