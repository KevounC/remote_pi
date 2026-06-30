# Wave run notes — bold-refactor autopilot drainer (2026-06-30)

Transient run log for the autopilot draining pass. Lives at `.work/` root
(transient, no frontmatter required). Delete when the campaign completes.
Per dispatch-economy capsule, dispatch rationale lives here when it affects
bundling/wave width.

## Environment (resolved this session)

- Flutter: `~/projects/remote_pi/.tools/flutter` (not on PATH; call binary directly)
- Pub cache: `~/projects/remote_pi/.pub-cache` (gitignored, writable; default
  `/home/agent/.pub-cache` is read-only)
- `app/`: `flutter pub get` online OK (no git deps).
- `cockpit/`: `flutter pub get --offline` REQUIRED (3 git deps from
  github.com/jacobaraujo7/* can't clone — global git insteadOf rewrites
  https→ssh, no SSH key; bare mirrors in .pub-cache/git/cache/ resolve offline).
- Known-unrelated analyze info: `axisAlignment` deprecated at
  `app/lib/ui/chat/widgets/input_bar.dart:802` — do not fail reviews on it.
- **pi-extension pnpm**: `/home/agent/.cache` is read-only; pnpm 11.x fails with
  `[ERR_SQLITE_ERROR]` unless store/caches are redirected. Use:
  `export PNPM_HOME=~/projects/remote_pi/.pnpm-store npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`
  + `corepack pnpm install --store-dir ~/projects/remote_pi/.pnpm-store` if
  node_modules missing. `/home/agent/.npmrc` is a broken char device (harmless
  EACCES warning — ignore). `pnpm test` full suite has known env UDS/cwd-lock
  failures (EPERM on /tmp/claude/*.sock); rely on typecheck + targeted vitest.
- **relay cargo**: clean `cargo clippy --all-targets` passes (a stale build
  artifact can make first-run clippy look red; rebuild clears it).
- node codegen (`tools/protocol-codegen/bin/protocol-codegen.mjs`): works,
  node v24.18.0.

## Wave 1 — launched 2026-06-30 (5 parallel, openai-codex/gpt-5.5)

Re-work of 5 of the 7 bounced stories. Disjoint ownership → safe parallel writes.

| Agent | Story | Subproject | Owns |
|---|---|---|---|
| dbe7b9bb | cockpit-workspace-projection-settings-split-step-3 | cockpit/ | connectivity panel + test (fake VM/gateway coverage) |
| 03d2f8c1 | split-pi-extension-index-composition-root-step-3 | pi-extension/ | index.ts wiring of legacy_ports adapters |
| 09224f9a | generated-protocol-dart-codegen-step-2 | app/+tools/ | protocol.g.dart regen match |
| 32d03993 | canonical-session-identity-model-step-4 | relay/ | outer.rs fail-closed + remove session_id from RoomMeta |
| b4c08246 (queued) | transcript-event-log-projection-derive-step-3 | app/ | sync_service.dart 3 fixes |

## Wave 1b — deferred (file collisions with Wave 1)

Run after the colliding partner lands:
- generated-protocol-rust-codegen-step-2 (relay) — collides on outer.rs with
  identity-model-step-4. Waits for 32d03993.
- canonical-session-wire-discriminator-step-3 (app) — collides on
  sync_service_test.dart/ws_transport.dart with transcript-projection-derive.
  Waits for b4c08246.

## Review pass

After Wave 1+1b land, run fresh-context gpt-5.5 reviews on each (cross-model
advisory; stories fast-advance on verification). Contract: approve →
review→done + `## Review`; bounce → review→implementing + `## Review bounce`;
commit `review: <slug> (<verdict>)`.

## Coordination rules given to every agent
- cwd is /home/agent/projects/remote_pi (NOT forks/).
- Stage files explicitly; NEVER `git add -A`/`git add .` (avoid staging .key/.pem).
- Leave .key/.pem untracked.
- Use the exact flutter/pnpm/cargo incantations above.

---

## Wave 2 — launched 2026-06-30 (fresh-context autopilot drain continuation)

State at pickup: **51 done / 0 review / 85 implementing / 4 drafting**. Bounce
backlog fully cleared (7/7 from Wave 1+1b). Probed ready-set (deps all `done`):
**19 stories ready**.

### Collision map (file-overlap → must serialize within cluster, parallel across)

- relay `pi_forward.rs`/`registry.rs`: `wire-discriminator-step-4` (makes the
  room-targeting change) + `relay-opaque-targeting-step-4` (locks with tests) →
  serialize W2 → W3.
- relay `handlers/peer.rs`: `relay-typed-actor-control-handlers-step-4` +
  `generated-protocol-rust-codegen-step-3` → serialize W2 → W3.
- app `connection_manager.dart`: `reachability-contract-app-adapter-step-2`
  (PREVIOUSLY BOUNCED) + `turn-state-machine-projection-consumers-step-2` +
  `canonical-session-identity-model-step-5` → serialize across W2/W3/W4.
- pi-extension **god-file `index.ts`** (6 ready stories touch it:
  composition-root-step-4, owner-multiplexer-step-2, sdk-session-projection-step-2,
  cli-daemon-pairing-step-3, transcript-projection-derive-step-4,
  turn-state-machine-late-attach-step-3) + `extension.test.ts` (5 stories) →
  **only ONE index.ts-writer per wave**; serialize the pi-ext front.

### Wave 2 — 9 single-item bundles, fully file-disjoint (cross-bundle overlap checked)

| Agent ID | Story | Subproject | Model/Tier | Owns |
|---|---|---|---|---|
| 0cc84a87 | canonical-session-wire-discriminator-step-4 | relay | gpt-5.5 high | pi_forward.rs, registry.rs |
| adddf2a7 | relay-typed-actor-control-handlers-step-4 | relay | gpt-5.5 high | handlers/{control,connection_actor,peer}.rs, presence.rs, rooms.rs, metrics.rs |
| 7bcaee1e | canonical-session-app-attribution-hydration-step-2 | app | spark med | ws_transport.dart + demux test |
| 2ac948a2 | generated-protocol-dart-codegen-step-3 | app | gpt-5.5 high | generator (tools/protocol-codegen) + protocol.g.dart (regen) + protocol.dart + protocol_codegen tests |
| 076ffe59 | reachability-contract-app-adapter-step-2 (BOUNCED) | app | gpt-5.5 high | connection_manager.dart, reachability_adapter.dart, tests |
| 1f1e887f | cockpit-workspace-projection-settings-split-step-4 | cockpit | gpt-5.5 med | settings_page.dart, daemon_editor_dialog.dart, daemon panel widgets |
| fcc6d428 | cockpit-workspace-projection-workspace-document-step-4 | cockpit | gpt-5.5 high | cockpit_viewmodel.dart, workspace_document.dart, test |
| 8eb3ce14 | reachability-contract-pi-adapter-step-3 | pi-ext | spark med | mesh_node.ts (import replacement; avoids index.ts) |
| cc53b26d | turn-state-machine-algebraic-state-step-3 | pi-ext | gpt-5.5 med | turn_state.ts/test, turn_projection.ts, turn sections of extension.test.ts (sole ext.test.ts writer this wave; avoids index.ts) |

Dispatch rationale: cross-subproject is always disjoint; within-subproject the
two relay bundles are file-disjoint (R1 pi_forward/registry vs R2 handlers/*);
the three app bundles are file-disjoint (ws_transport vs protocol.g.dart vs
connection_manager); the two cockpit bundles are file-disjoint (settings UI vs
viewmodel); the two pi-ext bundles both AVOID index.ts and don't share files
with each other (mesh_node.ts vs turn_state.ts). Only #9 touches extension.test.ts
this wave. Max-4-concurrent queue means 5 agents wait for slots — expected.

### Deferred to later waves (by collision)
- W3: `canonical-session-relay-opaque-targeting-step-4` (locks R1 after
  wire-discriminator-step-4), `generated-protocol-rust-codegen-step-3` (R2 after
  control-handlers-step-4; generated-contract invariant applies),
  `turn-state-machine-projection-consumers-step-2` (app connection_manager.dart
  after reachability-app-adapter-step-2), and ONE pi-ext index.ts writer (pick by
  dependent-unblock value — transcript-projection-derive-step-4 unblocks a
  cockpit feature arc).
- W4+: `canonical-session-identity-model-step-5` (app+cockpit re-key, HIGH risk,
  after projection-consumers-step-2), remaining pi-ext index.ts stories
  serialized (composition-root-step-4, owner-multiplexer-step-2,
  sdk-session-projection-step-2, cli-daemon-pairing-step-3,
  turn-state-machine-late-attach-step-3).

### Review pass (after Wave 2 lands)
Fresh-context `gpt-5.5` cross-model advisory reviews per story (stories
fast-advance on verification). Bounced story reachability-app-adapter-step-2 gets
a review that specifically re-checks the retry-storm invariant from its bounce.
Contract: approve → review→done + `## Review`; bounce → review→implementing +
`## Review bounce`; commit `review: <slug> (<verdict>)`.

### Coordination rule (unchanged, learned the hard way)
Do NOT run `git add`/`git commit` while parallel write-subagents are in flight —
it can sweep in an agent's in-progress story transition. Agents commit their own
work; orchestrator commits only its own notes/docs when no agents are writing.

## ⚠️ ENV-CEILING FINDING (load-bearing for all future pi-ext agents)

**The sandbox kernel blocks Unix domain socket `bind()` with `EPERM` everywhere**
(verified: `/tmp`, `/var/tmp`, project dirs, `~/.pi` — all writable, but UDS
listen is forbidden — a namespace/seccomp restriction, NOT a permissions issue).
`acquireCwdLock` (src/session/cwd_lock.ts) creates a `.sock` UDS to pin a
per-cwd singleton; it CANNOT bind → returns `{ok:false}` → `src/extension.test.ts`
`beforeEach` setup bails silently for ~37 tests that exercise the extension
harness. `cwd_lock.test.ts` itself fails all 7 tests (same EPERM). `~/.pi/remote/locks`
is also on a READ-ONLY fs.

This is a verified PRE-EXISTING environmental ceiling (clean HEAD has the same
37 failures), NOT a code defect. **DO NOT require full `src/extension.test.ts`
green — it is impossible in this sandbox.** Future pi-ext implement agents must
use this signal:
1. `corepack pnpm typecheck` (clean).
2. Targeted vitest on the files they own.
3. `vitest run src/extension.test.ts -t "<their test fragments>"` (story-filtered).
4. Confirm they did NOT add NEW failures beyond the known 37 baseline.
This matches `.agents/rules/testing-integrity.md` Environment-issue category.

The transcript-projection-derive-step-4 and dart-codegen-step-4 Wave-4 agents
were given this env-ceiling briefing explicitly.

---

## Wave 2 results — 6/9 done (fast-lane verified by orchestrator)

| Story | Commit | Verdict |
|---|---|---|
| wire-discriminator-step-4 | 8bad735 | ✅ done (land-mode; regen/test lock genuine) |
| app-attribution-hydration-step-2 | 8efd13e | ✅ done (5 demux outcomes, 5/5 tests) |
| relay-typed-actor-control-handlers-step-4 | 1f8544c | ✅ done (120 relay tests, fmt/clippy green) |
| reachability-contract-app-adapter-step-2 (BOUNCED) | 38ab178 | ✅ done (bounce fixed: `onRelayConnectionEstablished` preserves retryAttempt; 0→1→2 ladder regression) |
| reachability-contract-pi-adapter-step-3 | 84402d8 | ✅ done (1,2,5,10,30s ladder+cap test) |
| cockpit-workspace-projection-settings-split-step-4 | 89658c5 | ✅ done (DaemonSettingsPanel extracted; 7/7 tests) |

Reviews: fast-lane (story + green verification → orchestrator independently
re-ran tests + read code + confirmed ownership; review skill authorizes fast-lane
for stories). The bounced story got deeper code+test verification of the specific
invariant. Each review committed `review: <slug> (approve)`.

Remaining Wave-2 in-flight at W3 launch: dart-codegen-step-3 (94+ tools,
generated-contract), cockpit-workspace-document-step-4 (58 tools, mid-refactor
_trees/_focused→_documents), turn-state-algebraic-step-3 (28 tools).

## Wave 3 — launched 2026-06-30 (4 disjoint bundles)

Re-probed ready-set after 6 W2 done: 14 newly-ready. Collision constraints
respected: relay `handlers/peer.rs` cluster (serialize — only 1 relay story this
wave), app `connection_manager.dart` (turn-state-projection-consumers owns it;
reachability-app-adapter-step-3 deferred to W4), pi-ext `index.ts` god-file
(serialize — NO index.ts-writer this wave; all 4 W3 pi-ext choices avoid it).

| Agent ID | Story | Subproject | Model/Tier | Owns |
|---|---|---|---|---|
| 72f6344a | canonical-session-relay-opaque-targeting-step-4 | relay | gpt-5.5 med | pi_forward_test.rs, pi_forward.rs (comments), registry.rs (comments) |
| 298076b5 | turn-state-machine-projection-consumers-step-2 | app | gpt-5.5 HIGH | session_state.dart, transcript_projection.dart, sync_service.dart, connection_manager.dart, chat_viewmodel.dart, sync/transport tests |
| 3d8451af | reachability-contract-pi-adapter-step-4 | pi-ext | spark med | relay_client.ts + test (avoids index.ts) |
| 1976838e | cockpit-workspace-projection-settings-split-step-5 | cockpit | gpt-5.5 med | settings_page.dart, settings_category_panel.dart (new), settings_category.dart, schedule panel/dialogs/tests |

Deferred to W4+ (by collision):
- relay `generated-protocol-rust-codegen-step-3` (peer.rs/auth/challenge.rs/frame.rs/generated control.rs — collides with relay-opaque-targeting's peer.rs).
- relay `relay-typed-actor-control-handlers-step-5` (handlers/peer.rs + registry.rs + rooms.rs — collides with relay-opaque-targeting).
- app `reachability-contract-app-adapter-step-3` (connection_manager_test.dart — collides with turn-state-projection-consumers' connection_manager.dart ownership).
- app `canonical-session-app-attribution-hydration-step-3` (depends on step-2 done; ready — bundle with W4 app cluster).
- app `canonical-session-identity-model-step-5` (HIGH-risk re-key; needs projection-consumers-step-2 done first per W4 plan).
- pi-ext `index.ts` god-file front (5 stories: composition-root-step-4,
  owner-multiplexer-step-2, sdk-session-projection-step-2,
  cli-daemon-pairing-step-3, transcript-projection-derive-step-4) — serialize one
  per wave starting W4 (pick transcript-projection-derive-step-4 first: unblocks
  a cockpit feature arc).
- pi-ext `turn-state-machine-late-attach-step-3` (mesh_node.ts/bridge.ts —
  collides with reachability-pi-adapter-step-4's relay_client.ts? No, disjoint;
  but collides with turn-state-algebraic's turn_state.ts if that's still in-flight.
  Re-check at W4 launch.)

Transient-tree note for W3 agents: the dart-codegen agent's uncommitted
`protocol.g.dart`/`protocol.dart` and the workspace-document agent's uncommitted
`cockpit_viewmodel.dart` may make whole-project `analyze` show transient errors
in THOSE files. W3 agents were told to run their targeted tests as the regression
signal and ignore analyze errors confined to other agents' in-flight files.

## Wave 3 results — 4/4 done (fast-lane verified by orchestrator)

| Story | Commit | Verdict |
|---|---|---|
| canonical-session-relay-opaque-targeting-step-4 | 62eaef2 | ✅ done (9 pi_forward tests: session_id opacity + room-targeted; stale comments removed) |
| reachability-contract-pi-adapter-step-4 | a227eaa | ✅ done (liveness constants from contract; 14/14 tests) |
| turn-state-machine-projection-consumers-step-2 | f890c8c | ✅ done (HIGH-risk convergence core: 55/55 tests, all terminal causes → idle; ChatViewModel single projection, no OR logic) |
| cockpit-workspace-projection-settings-split-step-5 | b0bdaff | ✅ done (ScheduleSettingsPanel + SettingsCategoryPanel; settings_page pure route shell; 22/22 tests; analyze clean) |

Plus env-ceiling triage on **turn-state-machine-algebraic-state-step-3** (commit
`b4d8539` implement + `21bc551` review-approve): the implement agent (cc53b26d)
refused to commit because full `extension.test.ts` wasn't green. Orchestrator
triaged via stash differential (clean HEAD = 37 fail/106 pass; with agent's
changes = 37 fail/110 pass → +4 passing, 0 broken) and committed on the agent's
behalf. The 37 failures are the UDS-EPERM env ceiling (see finding above), not a
code defect. Agent's own signals green: 16 turn_state + 6 story-filtered
extension convergence tests + typecheck.

Also done this wave's tail (Wave 2 stragglers that completed during W3):
- generated-protocol-dart-codegen-step-3 (`4ba0339`) ✅ done — regen-diff EMPTY
  verified by orchestrator (generated-contract invariant holds); 15/15 codegen tests.
- cockpit-workspace-projection-workspace-document-step-4 (`7201976`) ✅ done —
  `_trees`/`_focused`→`_documents`; 3/3 tests; whole-cockpit analyze clean.

**Session tally after W3: 64 done / 72 implementing / 0 review.**

## Wave 4 — launched 2026-06-30 (4 disjoint bundles)

14 ready after W3. Collision constraints: relay `peer.rs`/`registry.rs` cluster
(rust-codegen-step-3, control-handlers-step-5, projection-consumers-step-3 —
all collide) deferred to W5; pi-ext `index.ts` god-file serialized (ONE writer
this wave: transcript-projection-derive-step-4).

| Agent ID | Story | Subproject | Model/Tier | Owns |
|---|---|---|---|---|
| d9b05f5a | generated-protocol-dart-codegen-step-4 | app | gpt-5.5 high | protocol.dart (facade), codec.dart, control_frames.dart, protocol.g.dart (regen), protocol_test, generator |
| 8d0486b5 | transcript-event-log-projection-derive-step-4 | pi-ext | gpt-5.5 high | index.ts (SOLE writer), transcript_event.ts, transcript_projection.ts, ext.test.ts transcript sections (env-ceiling-aware verification) |
| fb094b41 | cockpit-workspace-projection-workspace-document-step-5 | cockpit | gpt-5.5 high | cockpit_viewmodel.dart, workspace_document_commands.dart (new), commands test |
| 829c7f28 | canonical-session-app-attribution-hydration-step-3 | app | gpt-5.5 high | boxes.dart, session_index_record.dart, SyncService keying, read repos, ChatViewModel keying |

Cross-bundle overlap check: #1 app-protocol vs #4 app-persistence — disjoint
(protocol files vs boxes/records/sync keying). #2 pi-ext sole index.ts writer.
#3 cockpit disjoint. All 4 disjoint from each other.
