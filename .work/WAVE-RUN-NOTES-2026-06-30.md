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
