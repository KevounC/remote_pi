---
id: epic-bold-generated-protocol-schema-source-step-1
kind: story
stage: done
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-generated-protocol-schema-source
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 1: Establish the canonical schema package and manifest

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / generated contracts  
**Files**: `protocol/package.json`, `protocol/README.md`, `protocol/schema/remote-pi.schema.json`, `protocol/schema/manifest.json`, `protocol/schema/defs/*.schema.json`

## Current State

The wire source is spread across handwritten mirrors and a drifted registry:

```ts
// pi-extension/src/protocol/types.ts
export type ClientMessage =
  | { type: "pair_request"; id: string; token: string; device_name: string }
  | { type: "user_message"; id: string; text: string; images?: WireImage[]; streaming_behavior?: StreamingBehavior }
  | { type: "session_sync"; id: string; limit?: number }
  | { type: "session_new"; id: string }
  | { type: "session_compact"; id: string }
  | { type: "model_set"; id: string; provider: string; model_id: string }
  | { type: "thinking_set"; id: string; level: ThinkingLevel }
  | { type: "list_models"; id: string };

// pi-extension/src/protocol/codec.ts
const SERVER_TYPES = new Set<ServerMessage["type"]>([
  "pair_ok", "pair_error", "user_input", "queued_message_state",
  "agent_chunk", "agent_done", "agent_message", "tool_request",
  "tool_result", "error", "cancelled", "pong", "bye", "session_history",
]);
```

`SERVER_TYPES` omits live server messages (`user_message`, `compaction`, `action_ok`, `action_error`, `models_list`), and `.orchestration/contracts/` is a hand-maintained parallel contract.

## Target State

Create a repo-root schema package whose source is standards-based JSON Schema 2020-12 plus a small manifest for generation metadata. TypeScript-native schema libraries may be generated/used by consumers, but the source is not TypeScript-specific.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://remote-pi.dev/schemas/remote-pi.schema.json",
  "title": "Remote Pi wire protocol",
  "$defs": {
    "uuid": { "type": "string", "format": "uuid" },
    "openJson": true,
    "sessionId": { "type": "string", "minLength": 1 },
    "turnId": { "type": "string", "minLength": 1 }
  },
  "oneOf": [
    { "$ref": "./app-pi-client.schema.json" },
    { "$ref": "./app-pi-server.schema.json" },
    { "$ref": "./relay-control.schema.json" },
    { "$ref": "./cross-pc.schema.json" },
    { "$ref": "./cockpit-control.schema.json" }
  ],
  "x-remote-pi": {
    "discriminator": "type",
    "profiles": ["compat", "canonical-session"],
    "transports": ["relay-jsonl", "pi-custom-event"]
  }
}
```

`protocol/schema/manifest.json` is the one registry used by later TS/Dart/Rust generators:

```json
{
  "schemaVersion": 1,
  "source": "json-schema-2020-12",
  "families": [
    { "id": "appPiClient", "transport": "relay-jsonl", "schema": "schema/app-pi-client.schema.json" },
    { "id": "appPiServer", "transport": "relay-jsonl", "schema": "schema/app-pi-server.schema.json" },
    { "id": "relayControl", "transport": "relay-jsonl", "schema": "schema/relay-control.schema.json" },
    { "id": "crossPc", "transport": "relay-jsonl", "schema": "schema/cross-pc.schema.json" },
    { "id": "cockpitControl", "transport": "pi-custom-event", "schema": "schema/cockpit-control.schema.json" }
  ]
}
```

## Implementation Notes

- Choose JSON Schema 2020-12 as the canonical source. It matches the current JSONL wire exactly, supports direct boundary validation, and can be consumed by TS/Dart/Rust generators without making TypeScript the source of truth.
- Use `x-remote-pi` metadata only for generator hints that JSON Schema cannot express portably (family names, compatibility profile, discriminator property, transport encoding).
- Keep the source side-by-side with current hand mirrors. This step must not swap runtime consumers.
- Include both a `compat` profile (validates current fixtures) and a `canonical-session` profile (marks `session_id`/`turn_id` requirements for the later canonical-session epic). This preserves behavior while avoiding a schema shape that blocks the locked target.

## Acceptance Criteria

- [x] `protocol/README.md` states that `protocol/schema/` is the canonical schema source for generated protocol work.
- [x] `protocol/schema/remote-pi.schema.json` and `protocol/schema/manifest.json` exist and enumerate all five message families.
- [x] The schema source uses JSON Schema 2020-12 and keeps generator-only facts under `x-remote-pi`.
- [x] No runtime app/extension/relay/cockpit consumer is switched in this step.
- [x] The implementation notes record the schema-language choice and rejected alternatives in the parent feature body.

## Rollback

Delete the new `protocol/` schema package and revert the parent item notes. Because this step is side-by-side only, rollback does not require changing app, extension, relay, or cockpit runtime code.

## Implementation Notes

Implemented inline by the bold-refactor implement-orchestrator because no subagent dispatcher is exposed in this delegated harness. Added the repo-root `protocol/` package with JSON Schema 2020-12 as the committed neutral source, a manifest enumerating the five families (`appPiClient`, `appPiServer`, `relayControl`, `crossPc`, `cockpitControl`), shared `defs/common.schema.json`, and placeholder family schemas for later schema-source steps. Runtime consumers are intentionally unchanged.

Rationale logged in `protocol/README.md`: JSON Schema matches the current JSONL wire and keeps the source language-neutral; Protobuf/Buf, TypeScript-native schemas, and custom IDL were rejected for the reasons recorded there. This keeps the short-term fork refactor compatible with a future patchbay migration.

Verification: `python3 -m json.tool` passed for `protocol/package.json`, `protocol/schema/*.json`, and `protocol/schema/defs/*.json`. No app/extension/relay/cockpit runtime checks were run because this step is side-by-side schema metadata only.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Verified commit `6d90a31`, the changed schema/package files, parent feature design decisions, and JSON validity with `python3 -m json.tool` across `protocol/package.json`, `protocol/schema/*.json`, and `protocol/schema/defs/*.json`. Runtime consumers remain unchanged as designed.
