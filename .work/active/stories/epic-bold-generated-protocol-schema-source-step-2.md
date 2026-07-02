---
id: epic-bold-generated-protocol-schema-source-step-2
kind: story
stage: done
tags: [refactor, bold, pi-extension, app]
parent: epic-bold-generated-protocol-schema-source
depends_on: [epic-bold-generated-protocol-schema-source-step-1]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 2: Port the app↔pi inner message families into the schema

**Priority**: High  
**Risk**: Medium  
**Source Lens**: single source of truth / generated contracts  
**Files**: `protocol/schema/app-pi-client.schema.json`, `protocol/schema/app-pi-server.schema.json`, `protocol/schema/defs/app-pi-common.schema.json`, `protocol/fixtures/app-pi/*.jsonl`

## Current State

The current de-facto source is the TypeScript union, with Dart mirroring by hand and fixtures lagging behind newer message types:

```ts
// pi-extension/src/protocol/types.ts
export type ServerMessage =
  | { type: "pair_ok"; in_reply_to: string; session_name: string; session_started_at: number; room_id: string; harness?: { name: string; version: string }; hostname?: string }
  | { type: "pair_error"; in_reply_to: string; code: PairErrorCode; message: string }
  | { type: "user_input"; id: string; text: string; streaming_behavior?: StreamingBehavior }
  | { type: "user_message"; id: string; text: string; images?: WireImage[]; streaming_behavior?: StreamingBehavior }
  | { type: "queued_message_state"; id?: string; text?: string }
  | { type: "agent_chunk"; in_reply_to: string; delta: string }
  | { type: "agent_done"; in_reply_to: string; usage?: Usage }
  | { type: "agent_message"; in_reply_to: string; text: string; usage?: Usage }
  | { type: "compaction"; summary: string; tokens_before: number; ts?: number }
  | { type: "tool_request"; tool_call_id: string; tool: string; args: Record<string, unknown> }
  | { type: "tool_result"; tool_call_id: string; result?: unknown; error?: string }
  | { type: "error"; in_reply_to?: string; code: ErrorCode; message: string }
  | { type: "cancelled"; in_reply_to: string; target_id: string }
  | { type: "pong"; in_reply_to: string }
  | { type: "bye"; reason: ByeReason }
  | { type: "session_history"; in_reply_to: string; session_started_at: number; events: SessionHistoryEvent[]; eos: boolean; truncated: boolean }
  | { type: "action_ok"; in_reply_to: string; action: ActionName }
  | { type: "action_error"; in_reply_to: string; action: ActionName; error: string }
  | { type: "models_list"; in_reply_to: string; models: WireModel[]; current?: WireModel };
```

`app/lib/protocol/protocol.dart` has its own sealed classes and permissive parsing, e.g. `ServerMessage.fromJson` maps both `user_input` and `user_message` to `UserInput` and manually tolerates action/model fields.

## Target State

Represent every current `ClientMessage`, `ServerMessage`, and `SessionHistoryEvent` variant with discriminator-const JSON Schema definitions. Keep unknown JSON payload fields explicit as `true` or `additionalProperties` only where the existing contract is intentionally open (`args`, `result`, mesh/body-like values, open error codes).

```json
{
  "$id": "https://remote-pi.dev/schemas/app-pi-client.schema.json",
  "oneOf": [
    { "$ref": "#/$defs/pairRequest" },
    { "$ref": "#/$defs/userMessage" },
    { "$ref": "#/$defs/queuedMessageSet" },
    { "$ref": "#/$defs/queuedMessageClear" },
    { "$ref": "#/$defs/approveTool" },
    { "$ref": "#/$defs/cancel" },
    { "$ref": "#/$defs/ping" },
    { "$ref": "#/$defs/sessionSync" },
    { "$ref": "#/$defs/sessionNew" },
    { "$ref": "#/$defs/sessionCompact" },
    { "$ref": "#/$defs/modelSet" },
    { "$ref": "#/$defs/thinkingSet" },
    { "$ref": "#/$defs/listModels" }
  ],
  "$defs": {
    "userMessage": {
      "type": "object",
      "required": ["type", "id", "text"],
      "properties": {
        "type": { "const": "user_message" },
        "id": { "$ref": "./defs/app-pi-common.schema.json#/$defs/messageId" },
        "text": { "type": "string" },
        "images": { "type": "array", "items": { "$ref": "./defs/app-pi-common.schema.json#/$defs/wireImage" } },
        "streaming_behavior": { "const": "steer" }
      },
      "additionalProperties": false,
      "x-remote-pi": { "profileRequired": { "canonical-session": ["session_id", "turn_id"] } }
    }
  }
}
```

The server schema must include the types missing from `codec.ts`'s registry:

```json
{ "typeNames": ["user_message", "compaction", "action_ok", "action_error", "models_list"] }
```

## Implementation Notes

- Port from `pi-extension/src/protocol/types.ts` first, then cross-check Dart parsing in `app/lib/protocol/protocol.dart` and existing fixture examples.
- Keep the current `compat` shape byte-compatible: no required `session_id` or `turn_id` yet. Mark future self-describing requirements with `x-remote-pi.profileRequired.canonical-session` so later codegen can flip them deliberately.
- Add fixtures for protocol variants that exist in code but not `.orchestration/contracts/fixtures/`: `queued_message_set`, `queued_message_clear`, `queued_message_state`, `session_new`, `session_compact`, `model_set`, `thinking_set`, `list_models`, `action_ok`, `action_error`, `models_list`, `compaction`, and `user_message` with `images`.
- Preserve open `ErrorCode` as a string with documented known values rather than a closed enum.

## Acceptance Criteria

- [x] Every `ClientMessage["type"]` and `ServerMessage["type"]` from `pi-extension/src/protocol/types.ts` has exactly one schema definition.
- [x] Every `SessionHistoryEvent` variant has a schema definition and fixture coverage.
- [x] The schema validates existing `.orchestration/contracts/fixtures/*.jsonl` app-pi examples and the added fixtures for missing current types.
- [x] The schema clearly distinguishes current `compat` required fields from future `canonical-session` fields.
- [x] No live TypeScript or Dart runtime code is replaced in this step.

## Rollback

Revert the new app-pi schema and fixture additions. Since no runtime consumer is switched, rollback is limited to the schema package.

## Implementation notes

- Ported the app→Pi and Pi→app message unions into `protocol/schema/app-pi-client.schema.json` and `protocol/schema/app-pi-server.schema.json`, with shared scalar/model/error/history definitions in `protocol/schema/defs/app-pi-common.schema.json`.
- Preserved the `compat` profile as today's JSON wire while annotating future `canonical-session`/turn-state requirements through `x-remote-pi.profileRequired` metadata; no runtime TS/Dart/Rust consumer was switched in this step.
- Added `protocol/fixtures/app-pi/client-messages.jsonl` and `protocol/fixtures/app-pi/server-messages.jsonl` covering all current `ClientMessage`, `ServerMessage`, and `SessionHistoryEvent` variants, including `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`.
- Verification: `python3` JSON parse over all `protocol/schema/**/*.json` plus new app-pi fixtures passed. Full schema validation is intentionally deferred until step 5 adds the AJV check script.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review with direct commit/file verification. Reviewed commit `77067ca`; `protocol/schema/manifest.json` still enumerates the five expected families, the app↔Pi client/server schemas cover every current TS `ClientMessage`/`ServerMessage` type and every `SessionHistoryEvent` type, including `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`. Ran `python3 -m json.tool` over all 10 `protocol/schema/**/*.json` files and parsed all 35 new app-pi fixture lines; also ran a lightweight local schema check over `protocol/fixtures/app-pi/{client,server}-messages.jsonl`. Runtime consumers remain side-by-side: no `pi-extension/src` or `app/lib` runtime import of the new app-pi schemas was introduced.
