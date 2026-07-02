---
id: gate-docs-session-id-stale-absent-claim
kind: story
stage: done
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# Docs still claim chat protocol messages are dispatched without `session_id`

## Severity
High

## Location
- `docs/ARCHITECTURE.md:170-188`
- `docs/SPEC.md:79-84`
- `docs/DECISIONS.md:84-90`

## Issue
Docs state that `session_id` is absent on common chat-bearing message types and that scoped messaging is still an active design gap.

## Evidence (current runtime)
- `pi-extension/src/index.ts` wraps outbound messages with `_withCurrentSession(...)`, adding `session_id` for `user_input`, `agent_chunk`, `agent_done`, `tool_result`, and related response/control traffic before broadcast.
- `app/lib/protocol/protocol.dart` defines generated session-scoped sets (`generatedSessionScopedClientMessageTypes`, `generatedSessionScopedServerMessageTypes`) for discriminator validation.
- `app/lib/data/sync/session_gate.dart` rejects scoped messages missing/foreign session IDs with explicit reasons (`missing_session_id`, `session_mismatch`, `active_session_unknown`).

## Required update
Update the above docs to reflect that session identity is enforced in the protocol flow today, and remove the “absent session_id” narrative. This should also link to the session-gate behavior and required mismatch reasons.
