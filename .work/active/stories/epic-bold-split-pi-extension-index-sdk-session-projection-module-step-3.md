---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-split-pi-extension-index-sdk-session-projection-module
depends_on: [epic-bold-split-pi-extension-index-sdk-session-projection-module-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 3: Move app action routing behind fresh SDK capability guards

## Current State
```ts
// pi-extension/src/index.ts
case "model_set":
  if (!_pi) {
    _sessionUnavailable(sender, msg.id, "Pi model API unavailable during session replacement");
    break;
  }
  void handleModelSet(_pi, (_lastEventCtx ?? _lastCtx) as ActionCtx | null, ensureModelRegistry(), sender, msg, _persistModelDefault);
  break;
case "thinking_set":
  if (!_pi) {
    _sessionUnavailable(sender, msg.id, "Pi thinking API unavailable during session replacement");
    break;
  }
  handleThinkingSet(_pi, sender, msg);
  break;
```

Prompt delivery has a fresh `_messageApi` recapture path after app-triggered `session_new`, but `model_set` and `thinking_set` still depend on `_pi`.

## Target State
```ts
// pi-extension/src/session/sdk_session_projection.ts
type FreshActionApi = AgentMessageApi & Partial<ActionPi> & Partial<ActionCtx>;

private currentActionPi(action: "model_set" | "thinking_set"): ActionPi | null {
  if (!this.actionApi) return null;
  if (action === "model_set" && typeof this.actionApi.setModel === "function") return this.actionApi as ActionPi;
  if (action === "thinking_set" && typeof this.actionApi.setThinkingLevel === "function") return this.actionApi as ActionPi;
  return null;
}

handleClientMessage(sender: PeerChannel, msg: ClientMessage): void {
  switch (msg.type) {
    case "session_new":
      void handleSessionNew(this.commandCtx, sender, msg, (freshCtx) => this.bindReplacementContext(freshCtx));
      return;
    case "model_set": {
      const pi = this.currentActionPi("model_set");
      if (!pi) return this.sessionUnavailable(sender, msg.id, "Pi model API unavailable for the current session");
      void handleModelSet(pi, this.freshActionCtx(), ensureModelRegistry(), sender, msg, this.persistModelDefault);
      return;
    }
    case "thinking_set": {
      const pi = this.currentActionPi("thinking_set");
      if (!pi) return this.sessionUnavailable(sender, msg.id, "Pi thinking API unavailable for the current session");
      handleThinkingSet(pi, sender, msg);
      return;
    }
  }
}
```

## Implementation Notes
- `withSession` recapture must bind fresh command context, event context, message API, action API if present, and session id in one module method.
- `sendPiMessage` and `wakeAgent` should use the same stale-context clearing discipline: stale SDK object is removed from the binding table and not retried forever.
- If the SDK does not expose model/thinking setters on replacement contexts, return a clear sender-scoped unavailable error. Do not call a known-stale pre-replacement API.
- Keep `actions/handlers.ts` dependency-injected; this story changes the caller/adapter, not the action semantics.

## Acceptance Criteria
- [ ] App `session_new` recaptures fresh capabilities in one module method.
- [ ] App prompt after `session_new` uses the fresh message API and never calls the stale API.
- [ ] App `model_set` and `thinking_set` after replacement use a fresh action API when the SDK exposes one, or return an explicit sender-scoped unavailable error without calling stale `_pi`.
- [ ] `cancel` and `session_compact` prefer the freshest `session_start`/replacement context and clear stale bindings on stale-context exceptions.
- [ ] Targeted stale-context tests cover prompt, compact/cancel, model, thinking, and list-models paths after `/new`/`/resume`/`/fork`/`/reload` simulation.
- [ ] `corepack pnpm typecheck` and targeted `corepack pnpm test -- extension actions` pass from `pi-extension/`.

## Risk
High. This is the main stale-context bug class. The safe failure mode is an explicit sender-scoped unavailable error, not reuse of a stale SDK object.

## Implementation
- Added fresh SDK capability bindings to `SdkSessionProjection`: replacement/session-start contexts now own the current message API, action API, command/event context wrappers, sender-safe unavailable fallback, and stale-context binding cleanup.
- Routed app `session_compact`, `session_new`, `model_set`, `thinking_set`, `list_models`, prompt delivery, and `sendMessage` through projection-owned fresh guards instead of falling back to stale `_pi` after session replacement.
- `session_new` now recaptures command context, event context, message API, action API, and remote session id through one replacement binding path; `_pi` is deliberately dropped so post-replacement model/thinking actions either use fresh setters or return explicit sender-scoped errors.
- Added stale-context tests for prompt/list-models after simulated `new`/`resume`/`fork`/`reload`, compact/cancel after the same replacement reasons, model/thinking fresh-action success after app `session_new`, and model/thinking unavailable errors when the replacement context exposes no fresh setters.
- Verification:
  - `corepack pnpm typecheck` passed.
  - `corepack pnpm build` passed.
  - Targeted stale-context vitest filter passed: 4 passed, 154 skipped, 0 failed.
  - Full `corepack pnpm exec vitest run src/extension.test.ts` result: 154 passed, 4 failed, 0 skipped in the file's current 158-test run. The four failures match the documented false-alarm/environment bucket by name: `after a clean reset, connect works again (flag is per-instance, not sticky)`, `join emits remote-pi:name-assigned with requested + assigned + changed`, `rename:<name> renames live (broker re-register + relay swap), process/session survive`, and `a second same-name agent joins as <name>#2 instead of being refused`.

## Rollback
Restore app action routing in `index.ts` and the prior `_pi`/`_lastCtx`/`_lastEventCtx` helper paths; keep the module shell unused if necessary.

## Review

Approved (2026-06-30). Independently re-ran (clean state): `corepack pnpm typecheck`
clean; `corepack pnpm build` clean; **full pi-ext suite 660 passed | 3 skipped |
0 failed (44 files)** — fully green (up from 656 — the agent's 8+ new stale-context
tests, +285 lines).

Stale-context safety verified (2× consistent): prompt/list-models after simulated
new/resume/fork/reload use fresh session_start ctx (not stale `_pi`); compact/cancel
after replacement use freshest ctx; model/thinking after app `session_new` use fresh
action API or return explicit sender-scoped unavailable errors (never stale `_pi`);
session_new recaptures command/event/message/action API + remote session id through
one replacement binding path; `_pi` deliberately dropped as stale fallback;
session_shutdown teardown — app user_message after shutdown does not call stale pi.
Existing listener-count invariant tests untouched and passing. Commit `23277c9`
scoped to pi-ext only (index.ts + extension.test.ts + sdk_session_projection guards);
collision guard held.
