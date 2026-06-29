---
id: story-fix-session-start-message-api-recapture
kind: story
stage: done
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: extension-0.5.4
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Prevent stale message API after session replacement

## Symptom

Live workstation and mobile sessions still reported app `user_message` rejection after session replacement/reload:

```text
[remote-pi] app user_message id=cli_019f0f35-bd35-7587-9a23-f3b44f2e007b: agent rejected incoming message: This extension ctx is stale after session replacement or reload.
internal_error: Agent rejected incoming message: This extension ctx is stale after session replacement or reload.
```

The mobile prompt appeared to be accepted/started before the app received the stale-context error, which suggests the delivery surface can still be the outgoing session's stale API in at least one replacement path.

## Root cause

`story-fix-stale-pi-api-after-app-session-new` recaptured `_messageApi` from the `withSession` callback when Remote Pi itself drives `ctx.newSession()`, but the outgoing instance still retained `_pi` after `session_shutdown`. If a late app message or reused module-instance path reached the router while `_pi` was stale, `_wakeAgent()` could fall back to that stale extension API and report the SDK's stale-context error to the mobile app.

Important constraint found during review: `session_start` provides only a base `ExtensionContext`, not the `ReplacedSessionContext` that includes `sendMessage`/`sendUserMessage`. So the safe surfaces are: a fresh extension factory invocation with a new `pi`, or the `withSession` replacement context when Remote Pi initiated the replacement.

## Implementation notes

- Updated `pi-extension/src/index.ts` so `session_shutdown` clears `_pi` as well as `_messageApi` and captured contexts.
- Kept app-driven `session_new` safe by rearming from the `withSession` `ReplacedSessionContext`, including restarting the relay if the same module instance was marked disposed by shutdown.
- Removed reliance on `session_start` as a message-delivery recapture point; it remains the safe base-context recapture for compact/cancel/UI only.
- Added regression coverage in `pi-extension/src/extension.test.ts` proving app `user_message` after `session_shutdown` does not call a stale `_pi` and does not leak the stale-context SDK error back to the app.
- Targeted verification passed after the review-bounce fix: `corepack pnpm test -- src/extension.test.ts -t "app user_message after session_shutdown|app session_new recaptures fresh message API|app prompt waits for async fresh message API rejection|steering sendUserMessage throw"` (577 passed, 3 skipped across selected Vitest run).
- `corepack pnpm --dir /home/agent/forks/remote_pi/pi-extension typecheck` passed after the review-bounce fix.
- Full verification passed: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` (577 passed, 3 skipped).
- Review pass approved with no blockers; reviewer noted coverage is handler-level rather than full relay wire path, but sufficient for the stale `_pi` failure mode.

## Acceptance

- [x] App `user_message` after session shutdown/replacement does not fall back to stale `_pi`.
- [x] App-driven `session_new` still recaptures the replacement-session message API via `withSession`.
- [x] Regression test covers stale `_pi` after shutdown.
- [x] Targeted and full `pi-extension` verification pass.
