---
source_handle: remote-pi-index-lifecycle
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/pi-extension/src/index.ts
provenance: source-direct
---

# Remote Pi `src/index.ts` lifecycle and room-state wiring

Paraphrased summary: `src/index.ts` is the Remote Pi extension factory and runtime coordinator. It registers Pi SDK hooks for input mirroring, model/thinking selection, streaming messages, tool telemetry, agent completion, working-state publication, compaction, session start, and session shutdown. It owns module-level relay/peer/room state, guarded UI/context access, room metadata updates, and routing of mobile client messages into Pi actions.

## Key passages

- Module state includes `_relay`, `_activePeers`, `_myRoomId`, `_myRoomMeta`, `_currentModel`, `_currentThinking`, `_meshNode`, `_lastCtx`, `_lastEventCtx`, and `_disposed`.
- Comments around `_disposed` explain that `session_shutdown` can land while deferred/async connect work is still in flight, so connect/join/start paths must check `_disposed` after awaits and avoid ghost broker/relay instances.
- `_safeUi` / `_currentUi` protect notification/footer/UI paths against stale contexts after session replacement or reload.
- `turn_start` publishes `working: true`; `turn_end` publishes `working: false`; compaction is manually bracketed because compaction does not run as a normal LLM turn.
- `session_start` refreshes `_lastEventCtx` to the freshest base session context; `session_shutdown` marks the outgoing instance disposed, clears captured contexts, and tears down relay/mesh state.
- Mobile actions in the client-message router include `session_new`, `session_compact`, `model_set`, `thinking_set`, and `list_models`; `approve_tool` is present as a forward-compatible/ignored message path.
- In daemon mode, `session_new` without a command context acknowledges, resets the mirror, and exits with `EXIT_DAEMON_FRESH_SESSION` so the supervisor can respawn a fresh session.
- `session_compact` does not flow through `message_end`; the file pushes a synthetic compaction marker into `_messageBuffer` so `session_sync` can replay it.

## Structural metadata

- Source type: TypeScript source
- Path: `/home/agent/forks/remote_pi/pi-extension/src/index.ts`
- Relevant areas: module state, UI/context helpers, Pi hook registration, room meta publication, client-message router, session action handling.
