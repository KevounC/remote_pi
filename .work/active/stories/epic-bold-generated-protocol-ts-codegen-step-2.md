---
id: epic-bold-generated-protocol-ts-codegen-step-2
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-ts-codegen-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# TS codegen step 2 — generated unions and shared value types

## Brief
Generate TypeScript unions and shared value types beside the current handwritten `pi-extension/src/protocol/types.ts`, proving that the schema/IR covers the compatibility wire before any import surface is switched.

## Current State

```ts
export type ServerMessage =
  | { type: "pair_ok"; in_reply_to: string; session_name: string; session_started_at: number; room_id: string }
  | { type: "user_message"; id: string; text: string; images?: WireImage[]; streaming_behavior?: StreamingBehavior }
  | { type: "models_list"; in_reply_to: string; models: WireModel[]; current?: WireModel };
```

## Target State

```ts
// GENERATED CODE - DO NOT EDIT.
export interface PairOk {
  type: "pair_ok";
  in_reply_to: string;
  session_name: string;
  session_started_at: number;
  room_id: string;
  harness?: { name: string; version: string };
  hostname?: string;
}

export interface ModelsList {
  type: "models_list";
  in_reply_to: string;
  models: WireModel[];
  current?: WireModel;
}

export type ServerMessage =
  | PairOk
  | PairError
  | UserInput
  | UserMessage
  | QueuedMessageState
  | AgentChunk
  | AgentDone
  | AgentMessage
  | Compaction
  | ToolRequest
  | ToolResult
  | ErrorMessage
  | Cancelled
  | Pong
  | Bye
  | SessionHistory
  | ActionOk
  | ActionError
  | ModelsList;
```

## Implementation Notes

- Generate every current `ClientMessage`, `ServerMessage`, `SessionHistoryEvent`, `WireImage`, `Usage`, `WireModel`, `ThinkingLevel`, `StreamingBehavior`, `ByeReason`, `PairErrorCode`, `KnownErrorCode`, and open `ErrorCode` shape.
- Keep output in `pi-extension/src/protocol/generated/` and test it against the handwritten exports before switching imports.
- Preserve optionality from today's compatibility wire; do not require canonical-session `session_id` fields in this step.
- Generated relative imports must include `.js` under NodeNext if the generator splits files.
- Avoid broad generated dependency imports outside `pi-extension/src/protocol/`.

## Acceptance Criteria

- [ ] Generated TS unions cover every variant currently in `types.ts`.
- [ ] Generated optional fields match the compatibility wire.
- [ ] `tsc --noEmit` compiles generated output under the pi-extension TS config.
- [ ] No production import is switched yet.

## Risk
Medium — generated type names and exported aliases must match the current public import surface closely enough to support the Step 4 facade swap.

## Rollback
Remove generated TS output and tests; the hand-authored `types.ts` remains live.
