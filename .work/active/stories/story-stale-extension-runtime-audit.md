---
id: story-stale-extension-runtime-audit
kind: story
stage: implementing
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-fix-stale-pi-api-after-app-session-new]
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

## Acceptance

- Produce an evidence-backed classification of remaining stale-runtime surfaces.
- For each candidate, label it: already guarded, safe by construction, small fix applied, or follow-up filed.
- Add regression tests for any small hardening done in this story.
- Do not bundle a broad refactor; if the audit finds larger architecture work, file a follow-up item.
- Move to `review` with verification notes.
