---
id: story-investigate-model-thinking-actions-after-session-replacement
kind: story
stage: drafting
tags: [pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [story-stale-extension-runtime-audit]
release_binding: null
gate_origin: null
status: superseded
superseded_by: epic-bold-split-pi-extension-index-sdk-session-projection-module
created: 2026-06-28
updated: 2026-06-28
---

# Investigate model/thinking app actions after session replacement

## Brief

The stale-runtime audit found that app `model_set` and `thinking_set` still route through module-level `_pi.setModel()` / `_pi.setThinkingLevel()`. After app-triggered `session_new`, Pi may mark the captured extension API stale. The immediate prompt path has a fresh `_messageApi`, but model/thinking APIs do not have an equivalent fresh replacement surface today.

## Root risk

After session replacement, valid app model/thinking actions may return `action_error` until a full reload/restart even though the session is otherwise usable.

## Expected investigation

Add regression tests that simulate app `session_new` followed by `model_set` and `thinking_set` against a stale `_pi`. If the tests confirm stale failures, decide whether the fix belongs in Remote Pi (fresh action API wrapper, alternate ctx path, graceful user-facing error) or needs a Pi SDK change to expose fresh model/thinking setters on `ReplacedSessionContext` or `session_start` context.
