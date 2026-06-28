---
id: story-implement-extension-queued-message-protocol
kind: story
stage: implementing
tags: [pi-extension, app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Implement Pi-extension queued-message protocol

`PROTOCOL.md` and the app expose `queued_message_set` / `queued_message_clear`, but adversarial review found the live pi-extension dispatcher does not handle them.

## Scope

- Implement `queued_message_set`, `queued_message_clear`, `queued_message_state`, `session_sync` replay, and drain semantics in `pi-extension/src/index.ts` or an extracted helper.
- Drain the queued text as a normal `user_message` when the active turn completes and no current turn remains.
- Keep queue in Pi-side memory only; do not add relay offline queueing.

## Acceptance Criteria

- [ ] `queued_message_set` broadcasts current queued state to all owners.
- [ ] `queued_message_clear` clears and broadcasts empty queued state.
- [ ] `session_sync` includes the current queued state before/with history per `PROTOCOL.md`.
- [ ] When the current turn ends, queued text is sent once as a normal user message and the queued state clears.
- [ ] Add pi-extension tests for set, clear, sync replay, and drain.
