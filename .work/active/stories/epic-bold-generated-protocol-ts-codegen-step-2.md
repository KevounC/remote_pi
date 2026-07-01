---
id: epic-bold-generated-protocol-ts-codegen-step-2
kind: story
stage: review
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-ts-codegen-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] Generated TS unions cover every variant currently in `types.ts`.
- [x] Generated optional fields match the compatibility wire.
- [x] `tsc --noEmit` compiles generated output under the pi-extension TS config.
- [x] No production import is switched yet.

## Risk
Medium — generated type names and exported aliases must match the current public import surface closely enough to support the Step 4 facade swap.

## Rollback
Remove generated TS output and tests; the hand-authored `types.ts` remains live.

## Implementation

Implemented generated TypeScript unions and shared app/Pi value types in the generator, then regenerated `pi-extension/src/protocol/generated/protocol.generated.ts` from the schema. Runtime imports remain unchanged; `pi-extension/src/protocol/types.ts` is still the live handwritten facade for production code.

- Generator changes: `tools/protocol-codegen/src/index.ts` now emits schema-derived shared value types (`WireImage`, `Usage`, `WireModel`, `ThinkingLevel`, `StreamingBehavior`, `ByeReason`, `PairErrorCode`, `KnownErrorCode`, open `ErrorCode`, and `SessionHistoryEvent`) and uses those names in `ClientMessage` / `ServerMessage` variants instead of inlining every nested shape.
- Union emission: app/Pi variants now emit stable message interface names (`PairOk`, `ModelsList`, `ErrorMessage`, etc.) and unions matching the current compatibility variant set. Duplicate app/server `UserMessage` is emitted once and reused in both unions.
- Optionality: compatibility-profile generation keeps `session_id` available but optional, including `PairOk`, so this step does not enforce canonical-session fields.
- Generator tests: `node --test tools/protocol-codegen/src/index.test.ts` — 4 passed / 0 failed. The added test asserts real Remote Pi union/value-type output and variant coverage against the current handwritten protocol surface.
- Determinism proof: generated twice to two temp dirs and `diff -r` was empty.
- Regen-diff proof: generated to a temp dir and `diff -u` against `pi-extension/src/protocol/generated/protocol.generated.ts` was empty; `--check true` also passed.
- Pi-extension typecheck: `corepack pnpm typecheck` from `pi-extension/` with repo-local caches passed.
- Pi-extension vitest: orchestrator command fell back to `pi-extension` and ran 674 tests: 605 passed / 66 failed / 3 skipped. Failures are the pre-existing sandbox UDS/cwd-lock environment class (`listen EPERM`, leader-election/cwd-lock failures), not generated-protocol failures.

No production import was switched in this step.
