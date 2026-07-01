# Session note — 2026-06-30 (FINAL) — bold-refactor autopilot drain COMPLETE

Transient handoff note at `.work/` root (no frontmatter). Supersedes earlier
2026-06-30 session notes. Delete when the operator confirms the campaign is
shipped. Per `.agents/rules/agent-discipline.md` this is NOT a durable artifact.

## TL;DR — campaign complete

Operator asked to clear pre-existing test failures before continuing the drain,
then keep draining. This session did both and **completed the entire bold-refactor
campaign.**

**Final board: 173 done / 0 implementing / 0 blocked / 0 ready / 6 drafting.**
Every story, feature, and epic in the bold-refactor campaign is `done`. The 6
`drafting` items are future-work seeds (next campaign's intake, not leftovers).
**165 commits this session.**

### Done breakdown
- 8 root epics done (`.work/active/epics/`)
- 29 features done (`.work/active/features/`)
- 136 stories done (`.work/active/stories/`)

## Test baselines — ALL FULLY GREEN at HEAD (`cb58ed2`)
- **pi-ext: 718 passed | 3 skipped (44 files)**; typecheck clean.
  (Started at 648 with 25 failing → cleared debt, +70 tests added alongside refactors.)
- **app: 614 passed** (started ~597, +17).
- **cockpit: 231 passed** (started 226, +5).
- **relay: 158 passed** (unchanged — its arcs were done earlier in a prior session).

## What the campaign delivered (8 root epics, all complete)
1. `split-pi-extension-index` — decomposed the `index.ts` god-file into 5 modules
   (owner-multiplexer, cli-daemon-pairing, composition-root, relay-transport,
   sdk-session-projection). `index.ts` is now thin wiring.
2. `relay-typed-actor` — typed the relay actor model (frame-dispatch, control-handlers,
   registry-split). `PeerRegistry` is a thin facade over composed actor-state.
3. `generated-protocol` — generated protocol code across all 4 targets: TS, Dart,
   Rust, cockpit-control-RPC. pi-ext `types.ts`/`codec.ts` now use generated
   types/registries/validators; `check:protocol` guards against stale output.
4. `canonical-session` — canonical-session attribution (identity-model, wire-
   discriminator, app-attribution-hydration, relay-opaque-targeting).
5. `turn-state-machine` — algebraic-state, projection-consumers, late-attach.
   `working:false` convergence verified across all 7 paths.
6. `reachability-contract` — state-machine, pi-adapter, app-adapter.
7. `transcript-event-log` — projection-derive, store (canonical-session re-keyed
   Hive boxes), hydration-replay (deterministic replay adapter across app/pi-ext/cockpit).
8. `cockpit-workspace-projection` — workspace-document, agent-session, settings-split.

## ⚠️ Operator action: fresh app build + sideload required
The app's Hive persistence format changed this session (`transcript-event-log-store-step-4`
re-keyed boxes by canonical session: `transcript_events_<peer>__<room>__<session>`).
**Do NOT hot reload/restart** — the stale in-memory state vs new box names would mismatch.
- `pubspec.lock` also changed → `flutter pub get` first.
- Old peer+room boxes are PRESERVED (not deleted) — ignored on first launch; app
  re-syncs transcript history from the Pi on the canonical-session boundary.
- Optional cleanest: wipe app local data before first launch (avoids orphaned old boxes).
```bash
cd app
PUB_CACHE=~/projects/remote_pi/.pub-cache ~/projects/remote_pi/.tools/flutter/bin/flutter pub get
~/projects/remote_pi/.tools/flutter/bin/flutter build apk --debug   # or platform
```
Cockpit has schema-envelope control-command changes (`remote_pi_control`) — also
worth a fresh build if you want the structured control frames.

## ⚠️ CRITICAL PROCESS LESSONS (this session's most important findings)
Filed in `.work/backlog/backlog-piext-agents-false-uds-failure-claims.md`.

### 1. The false-failure briefing CAN MASK REAL REGRESSIONS
The recurring false-failure pattern (mesh/cwd-lock/UDS/`leader election`/
`supervisor.sock`/`rename:<name>`/`name-assigned`/`after a clean reset`) is real
(~16 agents hit it; last ~9 recognized it). BUT `relay-transport-module-step-5`
exposed a DANGEROUS failure mode — THREE consecutive agents used "this is the known
false-alarm pattern" as COVER to dismiss a REAL owner-ingress regression (duplicate
relay message-listeners). The orchestrator's independent vitest re-run was the ONLY
thing that caught it.

### 2. Runtime instrumentation beats agent static-analysis
Two step-5 agents GUESSED the duplicate-listener root cause wrong (theorized
`onOuterMessage` eager-registration). Runtime stack-trace instrumentation (temporary
`on()` override on `MockRelay` logging `new Error().stack`) revealed the true cause:
`attachCrossPcBridge` called 3× on connect, each creating a `PiForwardClient`
message-listener. **When an agent's claimed fix doesn't move the failure count,
instrument the runtime call paths — don't trust the agent's static theory.**

### 3. Orchestrator errors compound with agent misclassification
The orchestrator committed a WRONG test-fixture alignment based on a transient
dirty-tree observation (committed `toBe(2)`/`toBe(3)` when correct was
`toBe(1)`/`toBe(2)`). This broke the suite AND misled the next agent into copying
the wrong values + misclassifying. Reverted (`ea94508`/`5c5ae0b`). **Before changing
test expectations, verify observed counts against a CLEAN `git checkout` of HEAD
(run the test 5× for consistency), not a dirty debug tree.**

### Mitigations now in every HIGH-risk dispatch briefing (working — last ~6 agents correct):
1. Explicitly NAME the must-pass tests that assert behavior (not environment).
2. Positive discriminator: REAL failure = tests asserting listenerCount /
   routes-exactly-once / delivery counts / state transitions / session preservation /
   working-convergence. FALSE-alarm = names/errors mention leader-election /
   supervisor.sock / EPERM / broker.sock.
3. Orchestrator MUST independently re-run vitest on every pi-ext story against CLEAN
   state — the agent cannot be the sole arbiter.

### Also: ts-codegen steps 2-4 reproducibly showed "66 failed" transient spikes
in the agent environment (harness close timeout cascading). Clean orchestrator re-run
consistently showed 0. The orchestrator's clean re-run is the reliable gate; the
agent's full-suite count is NOT trustworthy when it shows a large failure spike.

## The 6 drafting items (future-work seeds — NOT campaign work)
- `feature-remote-pi-fork-vendor-and-mobile-surface` (fork divergence direction)
- `epic-remote-session-resilience-refactor` (new resilience arc)
- `story-add-transport-frame-observability`
- `story-stale-action-boundary-regression-tests`
- `story-remote-pi-mobile-mode-client-slice`
- `story-stale-command-ui-notify-guard`
These need design/drafting before implementable — next campaign's intake.

## Dev environment incantations (unchanged, load-bearing — keep for next campaign)
- **Flutter**: `~/projects/remote_pi/.tools/flutter/bin/flutter` (not on PATH).
  `/opt/flutter` is GONE.
- **Pub cache**: `PUB_CACHE=~/projects/remote_pi/.pub-cache` (default READ-ONLY).
  `app/` pub get online OK; `cockpit/` pub get `--offline` REQUIRED.
- **pi-extension pnpm**: `export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`.
- **relay cargo**: clean. `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
- **generated-contract regen-check (TS)**: from `pi-extension/`:
  `corepack pnpm check:protocol` (passes clean, fails if stale). From root:
  `corepack pnpm --dir pi-extension check:protocol`.
- **Runtime instrumentation trick** (listener-lifecycle debugging): add a temporary
  `on(ev,fn)` override to the test's `MockRelay` logging `new Error().stack`; run the
  single failing test; read the stacks to find duplicate-attach call sites. Remove
  before commit. VERIFY fixture changes against a clean `git checkout` before committing.

## Coordination rule (unchanged)
Stage files EXPLICITLY. NEVER `git add -A`/`.`. `*.key`/`*.pem` are untracked local
secrets — NEVER commit.
