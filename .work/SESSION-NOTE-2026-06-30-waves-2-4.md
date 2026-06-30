# Session note — 2026-06-30 — bold-refactor autopilot drain (Waves 2-4 done, W5 planned)

Transient handoff note at `.work/` root (no frontmatter). Delete when the
bold-refactor campaign completes. Per `.agents/rules/agent-discipline.md` this
is NOT a durable artifact — don't link durable docs at it.

## TL;DR — where the campaign stands after this session

Continued the bold-refactor autopilot drain. This session ran Waves 2, 3, and 4
to completion (17 stories advanced implementing→done), plus an env-ceiling
triage on one story. **No agents are in flight** — safe exit/resume point.

**Story stage counts:**
- Before this session: 51 done / 0 review / 92 implementing / 4 drafting
- After: **68 done / 0 review / 68 implementing / 4 drafting** (+17 done)

## ⚠️ CRITICAL ENV FINDING — the sandbox blocks Unix domain sockets

**The sandbox kernel blocks Unix domain socket `bind()` with `EPERM` everywhere**
(verified: `/tmp`, `/var/tmp`, project dirs, `~/.pi` — all writable, but UDS
listen is forbidden — a namespace/seccomp restriction, NOT a permissions issue).
`acquireCwdLock` (pi-extension/src/session/cwd_lock.ts) creates a `.sock` UDS to
pin a per-cwd singleton; it CANNOT bind → returns `{ok:false}` →
`src/extension.test.ts` `beforeEach` setup bails silently for ~37 tests that
exercise the extension harness. `cwd_lock.test.ts` itself fails all 7 tests.
`~/.pi/remote/locks` is also on a READ-ONLY fs.

This is a verified PRE-EXISTING environmental ceiling (clean HEAD has the same
37 failures), NOT a code defect. **DO NOT require full `src/extension.test.ts`
green — it is impossible in this sandbox.** If the session is rebuilt WITHOUT
the sandbox (the operator's plan), this ceiling may vanish — re-verify by
running `corepack pnpm exec vitest run src/session/cwd_lock.test.ts` from
`pi-extension/` (with the pnpm env vars). If cwd_lock tests pass, the UDS
ceiling is gone and full `extension.test.ts` is a valid signal again.

pi-ext verification signal (sandbox-limited):
1. `corepack pnpm typecheck` (clean).
2. `corepack pnpm exec vitest run <owned test files>`.
3. `corepack pnpm exec vitest run src/extension.test.ts -t "<test fragments>"`.
4. Confirm no NEW failures beyond the known 37 baseline.

## Dev environment incantations (resolved this session, in CLAUDE.md + skills too)

- **Flutter**: `~/projects/remote_pi/.tools/flutter` (not on PATH; call binary
  directly). `/opt/flutter` is gone.
- **Pub cache**: `~/projects/remote_pi/.pub-cache` (gitignored, writable).
  Default `/home/agent/.pub-cache` is READ-ONLY — always set
  `PUB_CACHE=~/projects/remote_pi/.pub-cache`. If HOME/config writability
  issues, `HOME=/tmp/pi-dart-home` (mkdir first).
- **`app/`**: `flutter pub get` online OK (no git deps). 1 known-unrelated
  analyze info: `axisAlignment` deprecated at
  `app/lib/ui/chat/widgets/input_bar.dart:802` — do NOT fail reviews on it.
- **`cockpit/`**: `flutter pub get --offline` REQUIRED (3 git deps from
  github.com/jacobaraujo7/* can't clone online — global git insteadOf rewrites
  https→ssh, no SSH key; bare mirrors in `.pub-cache/git/cache/` resolve
  offline). Keep that cache populated.
- **`pi-extension/` pnpm**: `/home/agent/.cache` is READ-ONLY; pnpm 11.x fails
  with `[ERR_SQLITE_ERROR]` unless caches redirected. `/home/agent/.npmrc` is a
  broken char device (harmless EACCES — ignore). Use:
  ```
  export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  export npm_config_cache=~/projects/remote_pi/.npm-cache
  export XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache
  corepack pnpm typecheck
  corepack pnpm exec vitest run <path>   # full pnpm test has the UDS env ceiling
  ```
- **`relay/` cargo**: clean. `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
  (A stale build artifact can make first-run clippy look red; `cargo clippy --all-targets` rebuild clears it.)
- **node codegen** (`tools/protocol-codegen`): works (node v24.18.0).

## Waves 2-4 results (all fast-lane verified by orchestrator)

### Wave 2 — 9/9 done
| Story | Commit | Notes |
|---|---|---|
| wire-discriminator-step-4 | 8bad735 | land-mode; regen/test lock (forward_to_room already present) |
| app-attribution-hydration-step-2 | 8efd13e | 5 demux outcomes; 5/5 tests |
| relay-typed-actor-control-handlers-step-4 | 1f8544c | 120 relay tests; fmt/clippy green |
| reachability-contract-app-adapter-step-2 (BOUNCED) | 38ab178 | bounce fixed: onRelayConnectionEstablished preserves retryAttempt; 0→1→2 ladder |
| reachability-contract-pi-adapter-step-3 | 84402d8 | 1,2,5,10,30s ladder+cap |
| cockpit-settings-split-step-4 | 89658c5 | DaemonSettingsPanel; 7/7 tests |
| generated-protocol-dart-codegen-step-3 | 4ba0339 | regen-diff EMPTY; 15/15 |
| cockpit-workspace-document-step-4 | 7201976 | _trees/_focused→_documents; analyze clean |
| turn-state-machine-algebraic-state-step-3 | b4d8539 | env-ceiling triage (agent refused to commit; orchestrator committed after stash-differential proof: +4 passing, 0 broken) |

### Wave 3 — 4/4 done
| Story | Commit | Notes |
|---|---|---|
| relay-opaque-targeting-step-4 | 62eaef2 | 9 pi_forward tests (session_id opacity + room-targeted); stale comments removed |
| reachability-pi-adapter-step-4 | a227eaa | liveness constants from contract; 14/14 |
| turn-state-projection-consumers-step-2 | f890c8c | HIGH-risk convergence core; 55/55; ChatViewModel single projection, no OR logic |
| cockpit-settings-split-step-5 | b0bdaff | ScheduleSettingsPanel; settings_page pure route shell; 22/22 |

### Wave 4 — 4/4 done
| Story | Commit | Notes |
|---|---|---|
| generated-protocol-dart-codegen-step-4 | 5e24b69 | protocol.dart 1313→20-line facade; regen-diff EMPTY + deterministic; 55/55 |
| cockpit-workspace-document-step-5 | 85a84eb | pure WorkspaceDocumentCommands + _applyWorkspaceCommand; 8/8; analyze clean |
| transcript-event-log-projection-derive-step-4 | 6df733d | _messageBuffer→_transcriptEvents; env-aware (6+23 filtered tests); 25 fail vs 37 baseline (fixed 12, broke 0) |
| canonical-session-app-attribution-hydration-step-3 | 0214c26 | HIGH-risk re-key; RemoteSessionRef; 72/72; rigorous two-session-id + legacy-box-not-deleted test |

## Resume instructions (full autopilot queue drain)

1. **All Waves 2-4 are `done`. No agents in flight. Working tree clean.**
2. **Re-verify the env ceiling first.** If the session is rebuilt without the
   sandbox, run `corepack pnpm exec vitest run src/session/cwd_lock.test.ts`
   from `pi-extension/` (pnpm env vars set). If it passes, the UDS ceiling is
   gone — pi-ext agents can use full `extension.test.ts` green as the signal
   again. If it still fails EPERM, keep the env-aware signal (typecheck +
   targeted vitest + `-t` filter + no-new-failures-beyond-37).
3. **Wave 5 ready-set: 14 stories** (probe with `python3 /tmp/full_probe.py` or
   the inline probe in `.work/WAVE-RUN-NOTES-2026-06-30.md`). Collision map:
   - **relay `peer.rs`/`registry.rs`/`rooms.rs` cluster** (serialize ONE per
     wave): `generated-protocol-rust-codegen-step-3`,
     `relay-typed-actor-control-handlers-step-5`,
     `turn-state-machine-projection-consumers-step-3` (this one is cross-cutting
     app `connection_manager.dart` + relay — careful).
   - **pi-ext `index.ts`** (serialize ONE writer per wave):
     `turn-state-machine-late-attach-step-3` (mesh_node.ts/bridge.ts/index.ts),
     plus the 4 deferred split stories (composition-root-step-4,
     owner-multiplexer-step-2, sdk-session-projection-step-2,
     cli-daemon-pairing-step-3).
   - **Newly-unblocked, mostly disjoint**: app-attribution-hydration-step-4
     (app transcript_event.dart/transcript_projection.dart),
     workspace-document-step-6 (cockpit viewmodel/workspace_projection/pane_item),
     dart-codegen-step-5 (app protocol_codegen parity tests + fixtures),
     transcript-projection-derive-step-5 (cockpit transcript entities + adapters),
     reachability-contract-app-adapter-step-3 (app reachability_adapter.dart).
4. **Suggested Wave 5 (5 disjoint bundles):**
   - `generated-protocol-rust-codegen-step-3` (relay R1 — sole relay writer;
     generated-contract invariant: change generator, regen, clean diff)
   - `app-attribution-hydration-step-4` (app transcript seam)
   - `workspace-document-step-6` (cockpit WorkspaceProjection adapter)
   - `dart-codegen-step-5` (app parity tests — disjoint from #2's transcript files)
   - `transcript-projection-derive-step-5` (cockpit transcript entities —
     disjoint from #3's viewmodel? CHECK: step-6 owns cockpit_viewmodel.dart,
     step-5 owns agent_session.dart/rpc_data_mapper/transcript entities —
     disjoint. Confirm at dispatch.)
   Defers: control-handlers-step-5 + projection-consumers-step-3 (relay
   collision with #1), late-attach-step-3 (pi-ext index.ts — start it as the
   ONE pi-ext writer if a slot is free, else W6), the 4 index.ts split stories
   (serialize after late-attach), reachability-app-adapter-step-3 (app
   reachability_adapter — disjoint, could swap in for width).
5. **Generated-contract invariant**: any story touching
   `relay/src/protocol/generated/*` or `app/lib/protocol/generated/*` must
   change the GENERATOR (`tools/protocol-codegen`), regenerate, and confirm a
   clean regen-diff (run twice for determinism). Never hand-edit generated files.
6. **Coordination rule (learned the hard way)**: do NOT run `git add`/`git
   commit` while parallel write-subagents are in flight — it can sweep in an
   agent's in-progress story transition. Agents commit their own work;
   orchestrator commits only its own notes/docs/review-advances when no agents
   are writing. Stage review-advance commits explicitly (only the story .md files).
7. **Reviews**: fast-lane for stories (confirm green verification → advance
   review→done; review skill authorizes this for stories). Orchestrator
   independently re-runs tests + reads code + confirms ownership + checks
   generated-contract invariant where relevant. Bounced/high-risk stories get
   deeper verification of the specific invariant.

## Detailed dispatch rationale
Lives in `.work/WAVE-RUN-NOTES-2026-06-30.md` (env incantations, agent IDs,
collision maps, Wave 2-4 dispatch tables, the env-ceiling finding).

## Untracked secrets
`*.key` / `*.pem` in the working tree are local secrets — correctly untracked,
NEVER commit. Every subagent staged files explicitly and left these alone.
