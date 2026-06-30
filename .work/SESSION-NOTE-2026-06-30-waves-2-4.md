# Session note — 2026-06-30 (cont) — bold-refactor autopilot drain in progress

Transient handoff note at `.work/` root (no frontmatter). Supersedes earlier
2026-06-30 session notes for current state. Delete when the bold-refactor
campaign completes. Per `.agents/rules/agent-discipline.md` this is NOT a
durable artifact — don't link durable docs at it.

## TL;DR — where the campaign stands now

Operator asked to clear pre-existing test failures before continuing the drain,
then keep draining. This session did both, then ran a continuous multi-wave
autopilot drain.

**Stage counts: ~136 done / ~36 implementing / 6 drafting** (was 68 done /
92 implementing at session start — +68 done, -56 implementing). **~135 commits.**

## Test baselines (all FULLY GREEN — test debt cleared)
- **pi-ext: 666 passed | 3 skipped | 0 failed (44 files)**; typecheck clean.
  (Start was 648 after clearing 25 pre-existing failures; baseline grew as agents
  added convergence/stale-context/reconnect/detached-no-op tests.)
- **app: 600 passed** (start ~597; grew with store/replay + sync regressions).
- **relay: 158 passed** (unchanged — relay arcs done earlier).
- **cockpit: 226 passed** (unchanged).

## ⚠️ CRITICAL PROCESS LESSONS (this session's most important findings)

### 1. THE FALSE-FAILURE BRIEFING CAN MASK REAL REGRESSIONS
The recurring false-failure pattern (mesh/cwd-lock/UDS/`leader election`/
`supervisor.sock`/`rename:<name>`/`name-assigned`/`after a clean reset`) is real
(~16 agents hit it; last ~9 recognized it). BUT: `relay-transport-module-step-5`
exposed a DANGEROUS failure mode — THREE consecutive agents used "this is the known
false-alarm pattern" as COVER to dismiss a REAL owner-ingress regression (duplicate
relay message-listeners), and the orchestrator's independent vitest re-run was the
ONLY thing that caught it.

### 2. Runtime instrumentation beats agent static-analysis
Two step-5 agents GUESSED the duplicate-listener root cause wrong (theorized
`onOuterMessage` eager-registration). Runtime stack-trace instrumentation
(temporary `on()` override on `MockRelay` logging `new Error().stack`) revealed
the true cause: `attachCrossPcBridge` called 3× on connect, each creating a
`PiForwardClient` message-listener. **When an agent's claimed fix doesn't move
the failure count, instrument the runtime call paths — don't trust the agent's
static theory.**

### 3. Orchestrator errors compound with agent misclassification
The orchestrator committed a WRONG test-fixture alignment based on a transient
dirty-tree observation (committed `toBe(2)`/`toBe(3)` when the correct values were
`toBe(1)`/`toBe(2)`). This broke the suite AND misled the next agent into copying
the wrong values + misclassifying. Reverted (`ea94508`/`5c5ae0b`). **Before changing
test expectations, verify observed counts against a CLEAN `git checkout` of HEAD
(run the test 5× for consistency), not a dirty debug tree.**

### MITIGATIONS now in every HIGH-risk dispatch briefing:
1. Explicitly NAME the must-pass tests that assert behavior (not environment).
2. Positive discriminator: REAL failure = tests asserting listenerCount /
   routes-exactly-once / delivery counts / state transitions / session
   preservation / working-convergence. FALSE-alarm = names/errors mention
   leader-election / supervisor.sock / EPERM / broker.sock.
3. Orchestrator MUST independently re-run vitest on every pi-ext story against
   CLEAN state — the agent cannot be the sole arbiter.
**Result: the last ~6 agents correctly classified false-alarms by reading actual
test names. The mitigation is working.**

## Epics advanced to done this session (15)
reachability-contract-state-machine (4/4), generated-protocol-schema-source (5/5),
cockpit-workspace-projection-workspace-document (6/6), transcript-event-log-projection-derive (6/6),
generated-protocol-rust-codegen (5/5), relay-typed-actor-control-handlers (6/5),
cockpit-workspace-projection-agent-session (5/5), relay-typed-actor-frame-dispatch (5/5),
split-pi-extension-index-owner-multiplexer-module (5/5), relay-typed-actor-registry-split (5/5),
split-pi-extension-index-cli-daemon-pairing-module (6/6), split-pi-extension-index-composition-root (5/5),
split-pi-extension-index-relay-transport-module (5/5), split-pi-extension-index-sdk-session-projection-module (5/5),
transcript-event-log-store (5/5).

## Major structural milestone: ALL 5 pi-ext split arcs DONE
The `index.ts` god-file decomposition is complete:
- owner-multiplexer (5/5) — command/mesh surface
- cli-daemon-pairing (6/6) — CLI/daemon/pairing command surface
- composition-root (5/5) — hooks/commands/ingress routed through ports
- relay-transport-module (5/5) — relay socket/reconnect/room-meta/bridge/owner-ingress
- sdk-session-projection-module (5/5) — session identity/transcript/turn/queue/late-attach/epoch
`index.ts` is now a thin wiring file. pi-ext baseline grew 648→666.

## Currently in flight
- NONE. All slots free. (transcript-event-log-store-step-5 just completed + epic advanced.)

## Resume instructions
1. **All slots free.** Ready stories (all pi-ext → serialize ONE writer per wave):
   - `generated-protocol-cockpit-control-rpc-step-2` (pi-ext files despite epic name)
   - `turn-state-machine-late-attach-step-4` (cross-cutting app+pi-ext tests)
2. **Newly-unblocked arcs** (check epic deps manually — probe mis-reads epic-level deps):
   - `generated-protocol-ts-codegen` (step-1..5) — dep `schema-source` epic IS done →
     actually unblocked. Fresh 5-step pi-ext arc (TS codegen, regen-check-gated).
   - `transcript-event-log-hydration-replay` (step-1..5, APP) — dep
     `transcript-event-log-store` epic just went done → WHOLE APP ARC UNBLOCKED.
     This is the next big cascade — app slot.
3. Arcs still implementing (15): canonical-session (4 arcs), generated-protocol
   (dart/ts/cockpit-rpc), reachability (app/pi-adapter), turn-state-machine
   (algebraic/late-attach/projection-consumers), cockpit settings-split. Several
   are 1 step from done.
4. Collision constraints: pi-ext `index.ts` (one pi-ext writer per wave); app/cockpit/relay free.
5. Generated-contract invariant: any story touching `relay/src/protocol/generated/*`
   or `app/lib/protocol/generated/*` MUST change the generator, regenerate, confirm
   clean regen-diff (run twice for determinism). Never hand-edit.

## Dev environment incantations (unchanged, load-bearing)
- **Flutter**: `~/projects/remote_pi/.tools/flutter/bin/flutter` (not on PATH).
  `/opt/flutter` is GONE.
- **Pub cache**: `PUB_CACHE=~/projects/remote_pi/.pub-cache` (default READ-ONLY).
  `app/` pub get online OK; `cockpit/` pub get `--offline` REQUIRED.
- **pi-extension pnpm**: `export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`.
- **relay cargo**: clean. `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
- **relay generated-contract regen-check**: from `protocol/`:
  `node --import tsx scripts/list-types.ts | node ../tools/protocol-codegen/bin/protocol-codegen.mjs --target rust --schema - --out-dir ../relay/src/protocol/generated --check`
  + determinism double-run + diff vs committed.
- **Runtime instrumentation trick** (listener-lifecycle debugging): add a temporary
  `on(ev,fn)` override to the test's `MockRelay` logging `new Error().stack`; run the
  single failing test; read the stacks to find duplicate-attach call sites. Remove
  before commit. VERIFY fixture changes against a clean `git checkout` before committing.

## Coordination rule (unchanged)
Do NOT `git add`/`git commit` while parallel write-subagents are in flight —
agents commit their own work; orchestrator commits only notes/docs/review-advances
when no agents are writing to those paths. Stage explicitly (never `-A`/`.`).
`*.key`/`*.pem` are untracked local secrets — NEVER commit.
