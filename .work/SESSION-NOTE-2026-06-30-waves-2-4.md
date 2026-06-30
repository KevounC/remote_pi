# Session note — 2026-06-30 (cont) — test-debt cleared + Wave 5 dispatched

Transient handoff note at `.work/` root (no frontmatter). Supersedes
`SESSION-NOTE-2026-06-30-waves-2-4.md` for current state. Delete when the
bold-refactor campaign completes. Per `.agents/rules/agent-discipline.md` this
is NOT a durable artifact — don't link durable docs at it.

## TL;DR — where the campaign stands now

Operator asked to clear pre-existing test failures before continuing the drain,
then keep draining. This session:

1. **Cleared all pre-existing pi-extension test debt** (commit `9aa2c42`) — 25
   failures across 2 files, all from the canonical-session attribution gate
   tightening (NOT caused by the drain).
2. **Advanced 2 stranded epics review→done** (commit `7d00e87`) — both had all
   children done; relay re-verified green (122 tests).
3. **Dispatched Wave 5** — 5 disjoint bundles, 4 running + 1 queued
   (max-4-concurrent gate). See dispatch table below.

## ⚠️ CRITICAL BASELINE CHANGE: pi-ext suite is now FULLY GREEN

Before this session: `extension.test.ts` 19 failed | 128 passed; `codec.test.ts`
6 failed. Now: **full pi-ext suite 640 passed | 3 skipped | 0 failed (43 files);
typecheck clean.**

**Wave 5+ pi-ext agents can now require full `extension.test.ts` GREEN for
their owned areas** — no more "no new failures beyond 19 baseline" caveat.
The fragile count-based check is retired. The masking risk on HIGH-risk
session-attribution stories is gone.

### What the test-debt fix was (so future agents understand the convention)

The canonical-session gate (`session_gate.ts`, added 2026-06-29 in
`identity-model-step-3`) requires a matching `session_id` on every
session-scoped client frame. 19 tests in `extension.test.ts` predated the gate
and emitted frames without `session_id` → correctly rejected as
`session_mismatch`. Fixed by routing fixtures through the captured canonical
session (same convention `transcript-projection-derive-step-4` used on 12
sibling tests). Three nuances:
- **session_start re-captures** the session id (fresh uuid when the ctx carries
  no sessionManager) → cancel cluster reads live id via
  `_getRemoteSessionIdForTest()`, not `currentSessionIdFromSends()`.
- **session_new swaps** the session id → post-new `user_message` carries the
  freshly-captured id.
- **post-shutdown user_message** → pin via `_setRemoteSessionIdForTest` so the
  frame reaches the `_disposed` guard the test targets (returns `internal_error`).
- empty `queued_message_state` now stamps `session_id` (correct); assertions
  relaxed to `toMatchObject({type})` + no `id`/`text` payload.

`codec.test.ts` (6 failures, same family): derived the server-fixture set from
the `session_scope` registry (single source of truth) so it can't drift again.

Full details in `.work/backlog/backlog-piext-extension-test-19-failures.md`
(marked resolved).

## Stage counts now

- After test-debt clear + 2 epics advanced: **70 done / 0 review / 68 implementing / 6 drafting** (+2 done).
- Wave 5 in flight (5 stories) will move 5 implementing→review on completion.

## Wave 5 — dispatched 2026-06-30 (5 disjoint bundles, all openai-codex/gpt-5.5)

Collision map respected: sole relay writer (#1), app split between sync/transcript
(#2) and protocol_codegen tests (#4, disjoint), cockpit split between
viewmodel/projection (#3) and transcript entities/mapper (#5, disjoint — #3
explicitly told NOT to edit agent_session.dart, owned by #5). NO pi-ext stories
this wave → index.ts god-file serialization doesn't bind.

| Agent ID | Story | Subproject | Thinking | Owns |
|---|---|---|---|---|
| c91389c1 | generated-protocol-rust-codegen-step-3 | relay | high | generated/control.rs, auth/challenge.rs, handlers/peer.rs, frame.rs + generator (generated-contract invariant: change generator, regen, clean diff) |
| 61709628 | canonical-session-app-attribution-hydration-step-4 | app | high | sync_service.dart (_applyHistory reducer), transcript_event.dart, transcript_projection.dart + tests (HIGH risk: hydration reducer rewrite) |
| 331b8527 | cockpit-workspace-projection-workspace-document-step-6 | cockpit | high | cockpit_viewmodel.dart, workspace_projection.dart (new), pane_item.dart + test |
| 0b0c0aa9 | generated-protocol-dart-codegen-step-5 | app | medium | app/test/protocol_codegen/ parity tests + fixtures + feature body verdict |
| 41a3531a | transcript-event-log-projection-derive-step-5 | cockpit | high | transcript_message.dart, transcript_event.dart, rpc_data_mapper.dart, agent_session.dart |

All stop at `stage: review`. Orchestrator runs the review pass (fast-lane for
stories: confirm green verification + ownership + read code; HIGH-risk #2
hydratration reducer gets deeper idempotency/pending-message verification).

## Deferred to Wave 6+ (by collision / serialization)
- relay `peer.rs`/`registry.rs` cluster: `relay-typed-actor-control-handlers-step-5`
  (collides with W5 #1's peer.rs), `turn-state-machine-projection-consumers-step-3`
  (cross-cutting app connection_manager.dart + relay).
- pi-ext `index.ts` god-file front (5 stories still ready:
  composition-root-step-4, owner-multiplexer-step-2, sdk-session-projection-step-2,
  cli-daemon-pairing-step-3, turn-state-machine-late-attach-step-3) — serialize
  ONE writer per wave. Pick `turn-state-machine-late-attach-step-3` first next
  wave (unblocks the most downstream).
- `canonical-session-identity-model-step-5` (HIGH-risk re-key; needs
  projection-consumers-step-3 done first).

## Dev environment incantations (unchanged, still load-bearing)

- **Flutter**: `~/projects/remote_pi/.tools/flutter` (not on PATH; call binary
  directly). `/opt/flutter` is gone.
- **Pub cache**: `PUB_CACHE=~/projects/remote_pi/.pub-cache` (default READ-ONLY).
  `app/` pub get online OK; `cockpit/` pub get `--offline` REQUIRED.
- **pi-extension pnpm**: `export PNPM_HOME=~/projects/remote_pi/.pnpm-store
  npm_config_cache=~/projects/remote_pi/.npm-cache XDG_CACHE_HOME=~/projects/remote_pi/.xdg-cache`.
- **relay cargo**: clean. `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
- **node codegen** (`tools/protocol-codegen/bin/protocol-codegen.mjs`): node v24.18.0.

## Coordination rule (unchanged)
Do NOT `git add`/`git commit` while parallel write-subagents are in flight —
agents commit their own work; orchestrator commits only its own notes/docs/
review-advances when no agents are writing. Stage explicitly (never `-A`/`.`).
`*.key`/`*.pem` are untracked local secrets — NEVER commit.

## Resume instructions
1. **5 Wave-5 agents in flight** (4 running + 1 queued). Wait for completions,
   then review-pass each (fast-lane stories; deeper verify #2's reducer).
2. pi-ext suite is now a clean baseline — Wave 6 pi-ext agents can require
   full `extension.test.ts` green for their owned areas.
3. After W5 reviews advance to done, probe ready-set again and dispatch W6
   (start with `turn-state-machine-late-attach-step-3` as the one pi-ext
   index.ts writer; add the deferred relay + app stories per collision map).
4. Generated-contract invariant: any story touching `relay/src/protocol/generated/*`
   or `app/lib/protocol/generated/*` must change the GENERATOR, regenerate,
   confirm clean regen-diff (run twice for determinism). Never hand-edit.
