---
id: epic-bold-generated-protocol-ts-codegen-step-3
kind: story
stage: done
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-ts-codegen-step-2]
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
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

- [x] Generated server registry includes `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`.
- [x] Generated validators accept representative current fixtures for all client/server variants.
- [x] Generated validators reject malformed objects with missing `type` or wrong required-field types.
- [x] No handwritten message-type allowlist remains in generated code.

## Implementation

- Extended `tools/protocol-codegen/src/index.ts` so the TS IR carries generated validator function bodies and the renderer emits schema-derived `CLIENT_MESSAGE_TYPES`, `SERVER_MESSAGE_TYPES`, `SESSION_HISTORY_EVENT_TYPES`, and self-contained compatibility predicates (`isClientMessage`, `isServerMessage`, `isSessionHistoryEvent`).
- Validators keep compatibility-session fields optional, preserve open JSON pockets for tool `args`/`result`, accept open `ErrorCode` strings, and enforce required property presence plus schema type/minimum/minLength checks.
- Regenerated `pi-extension/src/protocol/generated/protocol.generated.ts` via the code generator; no generated file was hand-edited.
- Added generator tests for drifted server registry entries, all app/Pi client and server variant fixtures, malformed missing/wrong-field rejection, open error-code/tool-result behavior, nested history-event registry validation, and deterministic output.
- Determinism double-run: two temp output dirs produced an empty `diff -r`.
- Regen-diff: a fresh temp regen matched `pi-extension/src/protocol/generated` with empty `diff -r`; fresh generated output is included in this commit.
- Verification: targeted generator node test passed (`5` tests); `corepack pnpm typecheck` passed. Full `corepack pnpm exec vitest run --reporter=dot` reached `606 passed`, `66 failed`, `3 skipped` (`675` total); failures are existing environment UDS/cwd-lock `EPERM`/leader-election sandbox failures unrelated to generated protocol output.

## Risk
Medium — validators must harden malformed inputs without accidentally rejecting valid compatibility payloads.

## Rollback
Remove generated validator/registry output and tests; Step 2 type generation can remain side-by-side.

## Review

Approved (2026-06-30) with GENERATED-CONTRACT verification. Independently verified
all three generated-contract invariants:
1. **Determinism double-run**: two temp dirs, `diff -r` EMPTY ✓
2. **No hand-edits**: regen-diff vs committed `protocol.generated.ts` EMPTY ✓
3. **pi-ext typecheck + suite**: clean; **672 passed | 3 skipped | 0 failed (44 files)** ✓

The agent reported "606 passed / 66 failed" — the same transient false-alarm spike seen
on step-2 (the agent noted "UDS/cwd-lock sandbox"). Clean orchestrator re-run: 0
failures, 672 passed (count held — generated registry/validator refinement, no new
runtime tests). This 66-failure spike is a reproducible agent-environment artifact,
NOT a real regression — the orchestrator's clean re-run is the reliable gate.

Commit `1a4c69a` scoped to tools/ + pi-ext only (generator `index.test.ts` +161 +
generated `protocol.generated.ts` +269); collision guard held. Runtime imports
unchanged. Generated registries + compatibility validators emitted via the generator.
Generator tests 5/5 passed.
