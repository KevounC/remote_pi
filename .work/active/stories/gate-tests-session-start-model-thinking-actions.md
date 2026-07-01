---
id: gate-tests-session-start-model-thinking-actions
kind: story
stage: implementing
tags: [testing, pi-extension]
parent: null
depends_on: []
release_binding: extension-0.6.0
gate_origin: tests
created: 2026-07-01
updated: 2026-07-01
---

# Add stale-context model/thinking action tests for session_start replacements

## Priority
Critical

## Spec reference
Item: `epic-bold-split-pi-extension-index-sdk-session-projection-module`

Acceptance criteria:

> App `model_set` and `thinking_set` after replacement use a fresh action API when the SDK exposes one, or return an explicit sender-scoped unavailable error without calling stale `_pi`.

> Targeted stale-context tests cover prompt, compact/cancel, model, thinking, and list-models paths after `/new`/`/resume`/`/fork`/`/reload` simulation.

## Gap type
missing test for lifecycle/state-convergence replacement variants

## Existing coverage mapped

- `pi-extension/src/extension.test.ts:1810` covers `model_set` and `thinking_set` after app-triggered `session_new` with a fresh action API.
- `pi-extension/src/extension.test.ts:1892` covers `model_set` and `thinking_set` after app-triggered replacement when no fresh action API exists.
- `pi-extension/src/extension.test.ts:1957` covers `session_start` replacement reasons `new`, `resume`, `fork`, and `reload`, but only for prompt delivery and `list_models`.
- `pi-extension/src/extension.test.ts:2023` covers `session_compact` and `cancel` after `new`, `resume`, `fork`, and `reload`.

No test found that sends `model_set` or `thinking_set` after `session_start` replacement reasons `resume`, `fork`, or `reload` and asserts the stale `_pi` action API is not called.

## Suggested test
```ts
// In extension.test.ts, extend the session_start replacement loop or add a sibling test:
test("model_set and thinking_set after new/resume/fork/reload use fresh session_start action API", async () => {
  // Arrange stale _pi.setModel/_pi.setThinkingLevel spies that throw if called.
  // For each reason: emit session_start with fresh setModel, setThinkingLevel,
  // modelRegistry, getModel, and sessionManager.getSessionId().
  // Send model_set and thinking_set with the fresh session_id.
  // Assert stale _pi setters were not called, fresh setters were called, and
  // sender-scoped action_ok replies were emitted.
});
```

## Test location (suggested)
`pi-extension/src/extension.test.ts` (near the existing stale-context replacement tests around `session_start replacement contexts for new/resume/fork/reload drive prompt and list_models without stale _pi`)

## Gate note
The tests scanner had to run inline in this harness because no source-read-only scanner sub-agent tool was exposed to this sub-agent context. The audit was grep-first against acceptance criteria and `describe`/`test` blocks, with targeted reads of matching regions only.
