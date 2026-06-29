---
id: story-stale-session-bound-surface-deep-audit
kind: story
stage: done
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-fix-session-start-message-api-recapture]
release_binding: extension-0.5.4
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Deep audit session-bound Remote Pi extension surfaces

## Brief

After repeated stale-context/stale-`pi` failures, perform a stricter invariant-based audit of `pi-extension/` session-bound surfaces. The previous audits found and fixed several cases, but missed `_pi` surviving `session_shutdown` as a fallback delivery surface. This audit must start from the invariant, not from known symptoms.

## Audit invariant

After `session_shutdown`, no late callback may use a session-bound SDK object from the outgoing runtime. Each app/relay/mesh path must either:

1. use a fresh `ReplacedSessionContext` from `withSession` for work caused by the same replacement operation;
2. use a fresh extension factory `pi` from the replacement runtime; or
3. return/drop a controlled error without touching session-bound SDK APIs.

Session-bound candidates include at least: `_pi`, `_messageApi`, `_lastCtx`, `_lastEventCtx`, command `ctx`, event `ctx`, `ctx.ui`, `ctx.abort`, `ctx.compact`, `ctx.newSession`, `ctx.modelRegistry`, `ctx.sessionManager`, and any extracted raw object or closure wrapping those objects.

## Scope

- Build a matrix of long-lived callbacks and app/relay/mesh routes against session lifecycle states: normal, during `session_shutdown`, after shutdown before rearm, after app-driven `withSession`, after fresh factory/session_start.
- Search for retained SDK/session objects and closures under `pi-extension/src/`.
- Verify every fallback candidate is either cleared on shutdown or stale-guarded.
- Classify each candidate: safe by invariant, already guarded, fixed now, needs follow-up.
- Add tests for any code changes made.

## Audit results

Three independent read-only passes plus direct grep/static inspection produced a stricter surface matrix.

| Surface | Classification | Evidence / disposition |
|---|---|---|
| `_pi`, `_messageApi`, `_lastCtx`, `_lastEventCtx` retained slots | guarded after latest fix | `session_shutdown` now clears all four; `_sendPiMessage` / `_wakeAgent` forget stale message APIs on SDK stale errors. |
| app `user_message` | guarded | uses `_wakeAgent`; after shutdown no stale `_pi` fallback remains; regression added in `story-fix-session-start-message-api-recapture`. |
| app `session_new` | guarded | `withSession` captures `ReplacedSessionContext` message API; prior tests cover fresh API and async rejection. |
| app `cancel` | guarded | `_abortCurrentTurn` prefers `_lastEventCtx`, catches stale abort contexts, and has replacement-boundary tests. |
| app `session_compact` | partially covered | code routes through `_lastEventCtx ?? _lastCtx`; missing extension-level `session_new → compact` regression. Filed `story-stale-action-boundary-regression-tests`. |
| app `model_set` / `thinking_set` | degraded/guarded, weakly tested | after latest fix they require live `_pi` and return controlled unavailable errors when `_pi` is absent; missing extension-level shutdown tests. Filed `story-stale-action-boundary-regression-tests`. |
| app `list_models` | likely guarded, weakly tested | no `_pi` use, but stale/fresh `ctx.modelRegistry` and `getModel` boundary lacks extension-level replacement regression. Filed `story-stale-action-boundary-regression-tests`. |
| relay-state `sendMessage` | guarded, weakly tested | `_emitRelayState` now skips when no message API is bound; missing explicit post-shutdown test. Filed `story-stale-action-boundary-regression-tests`. |
| auto-listener known-peer / pair_request reconnect | guarded | `_isCurrentStartedRelay(relay)` after awaits; prior tests cover late known-peer and pair_request after shutdown. |
| cross-PC bridge attach | gap already filed | `MeshNode.attachBridge()` / bridge discovery can install bridge listeners after teardown without a closed/epoch guard. Existing `story-fix-cross-pc-bridge-late-attach-after-shutdown` reconfirmed and expanded. |
| command helper `ctx.ui.notify` after awaits | main newly surfaced gap | many command helpers call raw `ctx.ui.notify(...)` after async work; if session replacement happens mid-command, UI access can throw stale-context errors. Filed `story-stale-command-ui-notify-guard`. |
| lower-level relay/client callbacks | mostly transport-only or listener-removal dependent | `RelayClient`, `PlainPeerChannel`, `PiForwardClient`, `BrokerRemote` generally do not own SDK ctx, but follow-up bridge work should add detach/late-frame tests where practical. |

## Follow-ups filed / updated

- `story-stale-command-ui-notify-guard` — new, for raw command UI notifications after awaits.
- `story-stale-action-boundary-regression-tests` — new, for replacement-boundary tests around app actions and relay-state.
- `story-fix-cross-pc-bridge-late-attach-after-shutdown` — existing, updated with reconfirmed bridge attach risk.

## Notes

No production code was changed in this audit story. It classifies remaining gaps and routes them into concrete child/follow-up stories rather than bundling another broad refactor.

## Acceptance

- [x] Audit matrix and classification recorded in this item.
- [x] All discovered gaps either fixed with tests or filed as follow-up stories.
- [x] Targeted/full verification run for any code changes. No code changes were made in this audit story.
- [x] Reviewer pass approves the audit/fixes or remaining follow-up split. Three read-only audit subagents completed; findings are represented above.
