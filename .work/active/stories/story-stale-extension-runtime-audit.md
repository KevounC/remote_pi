---
id: story-stale-extension-runtime-audit
kind: story
stage: done
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-fix-stale-pi-api-after-app-session-new]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Audit captured Pi runtime surfaces for stale-session hazards

## Brief

Proactively audit `pi-extension/` for the same stale-extension-runtime pattern that produced the repeated live errors after session replacement. The immediate `user_message` path has a targeted fix in `story-fix-stale-pi-api-after-app-session-new`; this story classifies the remaining long-lived callbacks and captured SDK/runtime objects so we can either harden small risks or file larger follow-up items.

## Scope

Inspect long-lived callback paths and module-level captured state, especially:

- captured `ExtensionAPI` / `_pi` action methods (`sendMessage`, `sendUserMessage`, model/thinking methods, command/tool APIs);
- captured `ExtensionContext` / command contexts (`_lastCtx`, `_lastEventCtx`, `ctx` passed into relay/mesh callbacks);
- relay and peer callbacks that outlive the command/event that created them;
- delayed continuations after `ctx.newSession`, `ctx.fork`, `ctx.switchSession`, or reload;
- app action paths: `session_new`, `session_compact`, `model_set`, `thinking_set`, `list_models`, `cancel`, and app `user_message`;
- mesh message delivery and `_sendPiMessage` use sites.

## Audit findings

Scanner pass `6592b264-55ff-41a` classified the remaining stale-runtime surfaces:

| Candidate | Classification | Outcome |
|---|---|---|
| Relay auto-listener known-peer and pairing paths after async `listPeers()` / `addPeer()` | small fix applied | Added `_isCurrentStartedRelay()` and post-await guards so late reconnect/pair continuations cannot attach owners or send replies after shutdown. |
| `_cmdStart` / `_cmdJoin` failure continuations after awaited connect operations | small fix applied | Replaced direct catch-path `ctx.ui.notify(...)` with `_notify(..., ctx)`, which tolerates stale UI contexts. |
| `MeshNode.attachBridge()` / cross-PC bridge async discovery | follow-up filed | Filed `story-fix-cross-pc-bridge-late-attach-after-shutdown`. |
| App `model_set` / `thinking_set` through module `_pi` after session replacement | follow-up filed | Filed `story-investigate-model-thinking-actions-after-session-replacement`. |
| PlainPeerChannel app message callback | safe by construction | It resolves `_lastEventCtx ?? _lastCtx ?? _noopCtx` at route time rather than closing over command ctx. |
| Relay reconnect and shutdown lifecycle | already guarded | Existing `_goIdle`, reconnect checks, and mid-connect tests cover the success path; this story added failure/late-continuation coverage. |

## Implementation notes

- Files changed: `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`.
- Follow-ups filed: `story-fix-cross-pc-bridge-late-attach-after-shutdown`, `story-investigate-model-thinking-actions-after-session-replacement`.
- Added regression tests:
  - `known-peer reconnect resolving after session_shutdown does not attach a ghost owner`
  - `pair_request resolving after session_shutdown does not attach or reply from the stale relay`
- Targeted verification passed: `corepack pnpm test -- src/extension.test.ts -t "known-peer reconnect resolving after session_shutdown|pair_request resolving after session_shutdown|app session_new recaptures fresh message API"` (575 passed, 3 skipped across the selected Vitest run).
- Review-bounce fix verification passed: `corepack pnpm test -- src/extension.test.ts -t "app session_new recaptures fresh message API|app prompt waits for async fresh message API rejection|steering sendUserMessage throw|known-peer reconnect resolving after session_shutdown|pair_request resolving after session_shutdown"` (576 passed, 3 skipped across the selected Vitest run).
- Full verification passed: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` (576 passed, 3 skipped).
- Review pass `28a2b874-3530-424` approved both stale-runtime stories with no blockers/important findings. Nit about `_wakeAgent()` doc-comment drift was fixed before close.

## Acceptance

- [x] Produce an evidence-backed classification of remaining stale-runtime surfaces.
- [x] For each candidate, label it: already guarded, safe by construction, small fix applied, or follow-up filed.
- [x] Add regression tests for any small hardening done in this story.
- [x] Do not bundle a broad refactor; if the audit finds larger architecture work, file a follow-up item.
- [x] Move to `review` with verification notes.
