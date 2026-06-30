---
source_handle: remote-pi-protocol-types
fetched: 2026-06-28
source_path: /home/agent/projects/remote_pi/pi-extension/src/protocol/types.ts
provenance: source-direct
---

# Remote Pi protocol types

Paraphrased summary: `src/protocol/types.ts` defines the TypeScript unions for client/app messages, server/extension messages, session history events, model/thinking metadata, and action names. These types describe the intended wire surface but do not alone prove runtime validation.

## Key passages

- `ClientMessage` variants include `pair_request`, `user_message` with optional images and streaming behavior, queued-message set/clear, `approve_tool`, `cancel`, `ping`, `session_sync`, `session_new`, `session_compact`, `model_set`, `thinking_set`, and `list_models`.
- `ServerMessage` variants include pairing responses, user/queued/agent/tool events, `compaction`, errors/cancellation, `pong`, `bye`, `session_history`, action responses, and `models_list`.
- `SessionHistoryEvent` includes replayable user input, tool request/result, agent message, and compaction marker events.
- `ActionName` is a closed union for `session_new`, `session_compact`, `model_set`, and `thinking_set`; `list_models` has a dedicated `models_list` response but is not included in that `ActionName` union.
- `ThinkingLevel` is redeclared as a wire enum rather than exposing SDK-internal types directly to the app.

## Structural metadata

- Source type: TypeScript source
- Path: `/home/agent/projects/remote_pi/pi-extension/src/protocol/types.ts`
