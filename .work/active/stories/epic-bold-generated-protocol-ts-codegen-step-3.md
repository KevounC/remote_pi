---
id: epic-bold-generated-protocol-ts-codegen-step-3
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-ts-codegen-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# TS codegen step 3 — generated registries and compatibility validators

## Brief
Generate schema-derived message registries and compatibility-profile validators so the TS codec can stop maintaining a separate allowlist and can fail fast on malformed boundary input.

## Current State

```ts
const SERVER_TYPES = new Set<ServerMessage["type"]>([
  "pair_ok",
  "pair_error",
  "user_input",
  "queued_message_state",
  "agent_chunk",
  "agent_done",
  "agent_message",
  "tool_request",
  "tool_result",
  "error",
  "cancelled",
  "pong",
  "bye",
  "session_history",
]);
```

This list omits schema-valid/live variants that are present in `ServerMessage`: `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`.

## Target State

```ts
// GENERATED CODE - DO NOT EDIT.
export const SERVER_MESSAGE_TYPES = [
  "pair_ok",
  "pair_error",
  "user_input",
  "user_message",
  "queued_message_state",
  "agent_chunk",
  "agent_done",
  "agent_message",
  "compaction",
  "tool_request",
  "tool_result",
  "error",
  "cancelled",
  "pong",
  "bye",
  "session_history",
  "action_ok",
  "action_error",
  "models_list",
] as const;

export type ServerMessageType = typeof SERVER_MESSAGE_TYPES[number];

export function isServerMessage(value: unknown): value is ServerMessage {
  const record = asRecord(value);
  if (!record || typeof record.type !== "string") return false;
  const validate = SERVER_MESSAGE_VALIDATORS[record.type as ServerMessageType];
  return validate?.(record) ?? false;
}
```

## Implementation Notes

- Generate `CLIENT_MESSAGE_TYPES`, `SERVER_MESSAGE_TYPES`, and nested history-event registries from the schema/IR.
- Generate self-contained predicate validators for the compatibility profile. Avoid adding an AJV runtime dependency to `pi-extension/` unless implementation proves the generated predicate route is unworkable.
- Keep open pockets open: tool `args`, tool `result`, unknown `ErrorCode`, and future-tolerant extra properties where the schema marks them open.
- Add tests that assert the drifted server variants appear in the generated registry.
- Keep canonical-session-only requirements as metadata until that feature enables the stricter profile.

## Acceptance Criteria

- [ ] Generated server registry includes `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`.
- [ ] Generated validators accept representative current fixtures for all client/server variants.
- [ ] Generated validators reject malformed objects with missing `type` or wrong required-field types.
- [ ] No handwritten message-type allowlist remains in generated code.

## Risk
Medium — validators must harden malformed inputs without accidentally rejecting valid compatibility payloads.

## Rollback
Remove generated validator/registry output and tests; Step 2 type generation can remain side-by-side.
