---
id: story-fix-stale-pi-api-after-app-session-new
kind: story
stage: done
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Fix stale Pi API after app-triggered session replacement

## Symptom

Live Remote Pi reported app-originated prompts failing after session replacement:

```text
[remote-pi] app user_message id=cli_019f0ca4-d00d-79f7-839c-2e7f15174d27: agent rejected incoming message: This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload().

[remote-pi] relay-state: Pi rejected message: This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload().
```

This resembles the earlier stale-context class but is on app `user_message` delivery rather than compact/cancel/footer handling.

## Root cause

The previous stale-context fix refreshed `_lastCtx` / `_lastEventCtx`, which protects `ctx.compact()`, `ctx.abort()`, UI, footer, and app action routing. App `user_message` delivery, however, still called the module-level `_pi.sendUserMessage()`. Pi invalidates the captured extension API after `ctx.newSession()` / session replacement just like it invalidates command contexts, so the next app prompt could still hit the old `_pi` object and be rejected as stale.

## Fix approach

Track the current message-delivery API separately from `_lastCtx` as `_messageApi` (`sendMessage` + `sendUserMessage`). Initialize it from the extension API at load, clear stale instances when they throw the stale-context error, and recapture the fresh message-capable `withSession` context after app-triggered `session_new`. Route both `_wakeAgent()` and `_sendPiMessage()` through this fresh message API before falling back to `_pi`.

## Regression tests

`pi-extension/src/extension.test.ts` adds:

- `app session_new recaptures fresh message API for the next app prompt`, which simulates app `session_new`, a stale old `_pi`, an async fresh `withSession` context, and a following app `user_message`. The test asserts the stale API is not called, the fresh API receives the prompt, and the app gets the normal echoed `user_message`.
- `app prompt waits for async fresh message API rejection before echoing`, added after review found that replacement-session `sendUserMessage()` / `sendMessage()` may be async. It asserts async rejection returns a correlated error and does not broadcast a success echo.

## Implementation notes

- Files changed: `pi-extension/src/index.ts`, `pi-extension/src/extension.test.ts`.
- Added `_messageApi` as the current message-delivery surface and recapture it from replacement `withSession` contexts.
- `_wakeAgent()` now awaits sync-or-async message APIs, clears stale candidates, and only echoes app prompts after delivery acceptance.
- `_sendPiMessage()` now attaches a rejection handler for async `sendMessage()` results to avoid unhandled promise rejections and clear stale candidates.
- Initial targeted regression: `corepack pnpm test -- src/extension.test.ts -t "app session_new recaptures fresh message API"` passed (full Vitest invocation selected all files; 573 passed, 3 skipped).
- Initial full verification: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` passed (573 passed, 3 skipped).
- Initial final post-dedupe check: `corepack pnpm typecheck` passed.
- Review pass `951908f6-41d9-485` bounced the first fix because the fresh `withSession` message API is async. The follow-up implementation made `_wakeAgent()` await sync-or-async APIs and added the async rejection regression above.
- Review-bounce targeted verification: `corepack pnpm test -- src/extension.test.ts -t "app session_new recaptures fresh message API|app prompt waits for async fresh message API rejection|steering sendUserMessage throw|known-peer reconnect resolving after session_shutdown|pair_request resolving after session_shutdown"` passed (576 passed, 3 skipped across the selected Vitest run).
- Review-bounce full verification: `corepack pnpm typecheck && corepack pnpm test && corepack pnpm build` passed (576 passed, 3 skipped).
- Final review pass `28a2b874-3530-424` approved the async-message-API fix with no blockers/important findings. Nit about `_wakeAgent()` doc-comment drift was fixed before close.
