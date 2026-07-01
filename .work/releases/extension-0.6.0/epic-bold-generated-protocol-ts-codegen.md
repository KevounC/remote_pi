---
id: epic-bold-generated-protocol-ts-codegen
kind: feature
stage: done
tags: [refactor, bold, pi-extension]
parent: epic-bold-generated-protocol
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: extension-0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Generated protocol — TypeScript codegen target

## Brief
Generate the TS unions + validators + codec registry from the canonical schema,
replacing `pi-extension/src/protocol/types.ts` and `protocol/codec.ts`. The
drifted `SERVER_TYPES` registry (missing `user_message`, `compaction`,
`action_ok`, `action_error`, `models_list`) becomes impossible — the generator
emits it from the schema.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: consumer of `schema-source`; TS is the most natural codegen target
  (TS-as-source or TS-as-emitted depending on the schema language chosen).

## Foundation references
- Evidence: `pi-extension/src/protocol/types.ts:1-213`, `codec.ts:3-18`,
  `transport/relay_client.ts:32` (`RoomMeta` omits `thinking`/`working`).

## Design decisions

- **Autopilot judgment mode**: no strategic questions asked. The TS target is designed from the already-landed generated-protocol sibling decisions and current `pi-extension/` source.
- **Misroute check**: keep this as `[refactor]`. The implementation preserves the current app↔Pi wire shape and stable import surface while replacing handwritten TypeScript unions, validators, and codec registries with generated output. Future required `session_id` / `turn_id` fields remain canonical-session work, not this refactor.
- **Schema input**: consume the repo-root `protocol/schema/manifest.json` and JSON Schema 2020-12 family schemas chosen by `epic-bold-generated-protocol-schema-source`. The TS target does not make TypeScript the schema source.
- **Codegen approach chosen**: build the TS emitter on the same deterministic schema/IR pipeline chosen by the Dart design, then emit TypeScript unions, variant registries, and self-contained validators under `pi-extension/src/protocol/generated/`. TypeScript is close enough to JSON Schema that direct generation is possible, but using the shared normalized IR avoids TS/Dart semantic drift and keeps the path portable to patchbay.
- **Rejected: `json-schema-to-typescript` as the primary path**. It can emit useful DTOs, but it does not also own exact runtime validators, codec registries, stable variant ordering, compatibility aliases, or generator parity with Dart/Rust. Using it plus a separate validator would recreate two interpretations of the same schema inside the TS target.
- **Rejected: TS-native schema-derived validators (`zod`/TypeBox) as the protocol source**. These libraries may be generated as implementation details later, but authoring TS schemas would undo the neutral JSON Schema source decision. For the first pass, generated self-contained predicates avoid adding an AJV runtime dependency to the Pi extension and make the generated boundary auditable.
- **Validator compatibility posture**: generated validators target the current compatibility wire. They preserve current optional fields, open JSON pockets (`args`, `result`, open `ErrorCode`), and extra-property tolerance where today's cast-based parser is permissive. The registry drift fix intentionally accepts live server variants omitted by the handwritten `SERVER_TYPES` set (`user_message`, `compaction`, `action_ok`, `action_error`, `models_list`).
- **Canonical-session coordination**: schema metadata may mark future `session_id`/`turn_id` requirements, but generated TS validators must not require those fields until the canonical-session implementation flips the profile.
- **Dispatch rationale**: direct-read only. This delegated worker has no subagent tool exposed despite the raised implementation tier; local grounding covered the foundation docs, sibling designs, TS protocol files, codec tests, and boundary parsers. Design-time advisory review is non-blocking under autopilot.
- **Cycle check**: `.work/bin/work-view --blocking` is unavailable in this checkout (`.work/bin/` is empty). Manual cycle check searched active items for existing references to `epic-bold-generated-protocol-ts-codegen`; only the parent epic and this feature reference it. New stories form a backward-only chain from the schema-source feature through step 5, so no dependency cycle is introduced.

## Code-smell scan findings

1. **Handwritten discriminated unions are the de-facto source** — `pi-extension/src/protocol/types.ts` defines `ClientMessage`, `ServerMessage`, shared value types, and history events by hand. High value: TS should become generated from the canonical schema rather than continuing as a local source of truth.
2. **Known registry drift in `codec.ts`** — the handwritten `SERVER_TYPES` set omits live `ServerMessage` variants (`user_message`, `compaction`, `action_ok`, `action_error`, `models_list`). High value: generated registries remove the drift class.
3. **Validation boundary is cast-based** — `decodeServer` only checks JSON/object/type/allowlist, and app-origin messages in `PlainPeerChannel._onLine` and `index.ts` are parsed then cast to `ClientMessage`. High value: generated validators can fail fast at the transport edge while preserving compatibility shape.
4. **Fixtures do not cover every live TS server variant as server-decodable** — `protocol/codec.test.ts` has a fixture allowlist that treats `user_message.jsonl` as client-only even though `ServerMessage` includes an echoed `user_message`. Medium/high value: generated parity tests should derive expected variant coverage instead of maintaining another list.
5. **Action vocabulary drift risk** — `ActionName` is handwritten separately from `ClientMessage` action variants; `list_models` has a dedicated response path rather than an `action_ok`, but the generator should make this distinction explicit in schema metadata instead of relying on comments.
6. **No project-specific refactor convention catalog** — `.agents/skills/refactor-conventions/` is absent, so no convention-driven step was added beyond the default refactor-design lenses.

## Refactor Overview

The TypeScript target should consume the neutral JSON Schema source through the same normalized schema/IR pipeline used by the Dart target, then emit TS code that becomes the stable source imported by `pi-extension/` runtime code. The migration is staged to keep behavior observable only as the intended registry drift fix:

1. Add a TS generator target and fixture/golden harness beside existing runtime code.
2. Generate TS unions and shared value types beside the handwritten `types.ts`.
3. Generate schema-derived variant registries and compatibility validators.
4. Replace `types.ts` and `codec.ts` with generated facades/codec adapters while preserving current imports and JSONL behavior.
5. Add parity checks and package scripts so generated TS output cannot drift from the schema.

The generated validators are compatibility-profile validators, not canonical-session enforcement. They should accept today's valid payloads, keep open JSON fields open, and tolerate future unknown error codes while failing malformed boundaries early.

## Refactor Steps

### Step 1: Add the TypeScript generator target and schema handoff

**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contracts / missing abstraction  
**Files**: `tools/protocol-codegen/`, `protocol/schema/manifest.json`, `pi-extension/src/protocol/generated/`, `pi-extension/src/protocol/generated/*.test.ts`  
**Story**: `epic-bold-generated-protocol-ts-codegen-step-1`

**Current State**:

```ts
// pi-extension/src/protocol/types.ts is authored by hand and acts as the
// de-facto source for TypeScript instead of consuming protocol/schema/.
export type ClientMessage =
  | { type: "pair_request"; id: string; token: string; device_name: string }
  | { type: "user_message"; id: string; text: string; images?: WireImage[]; streaming_behavior?: StreamingBehavior }
  | { type: "list_models"; id: string };
```

**Target State**:

```ts
// tools/protocol-codegen/src/index.ts
const manifest = await loadRemotePiManifest("protocol/schema/manifest.json");
const ir = await buildRemotePiIr(manifest, { profile: "compat" });
await emitTypeScriptProtocol(ir, {
  outFile: "pi-extension/src/protocol/generated/protocol.generated.ts",
});
```

**Implementation Notes**:

- Put shared generator logic under `tools/protocol-codegen/` so TS and Dart use the same normalized IR instead of separate schema walkers.
- The TS target waits for schema-source family schemas to be filled; if only placeholders exist, the generator should fail with a clear "schema family placeholder" error.
- Emit deterministic output order from `manifest.json`, not filesystem traversal.
- Do not switch `pi-extension/src/protocol/types.ts` or runtime imports in this step.

**Acceptance Criteria**:

- [ ] A TS generator target can load the protocol manifest and build a normalized IR.
- [ ] Placeholder/incomplete schema families fail with a clear diagnostic.
- [ ] A minimal fixture schema emits deterministic TS output in a generator test.
- [ ] Existing pi-extension runtime behavior is unchanged.

**Rollback**: delete the TS generator target and generated spike output; no runtime code depends on it.

---

### Step 2: Generate TypeScript unions and shared value types beside the hand mirror

**Priority**: High  
**Risk**: Medium  
**Source Lens**: duplicated variants / generated contracts  
**Files**: `pi-extension/src/protocol/generated/protocol.generated.ts`, `pi-extension/src/protocol/generated/protocol.generated.test.ts`, `pi-extension/src/protocol/types.ts` as reference  
**Story**: `epic-bold-generated-protocol-ts-codegen-step-2`

**Current State**:

```ts
export type ServerMessage =
  | { type: "pair_ok"; in_reply_to: string; session_name: string; session_started_at: number; room_id: string }
  | { type: "user_message"; id: string; text: string; images?: WireImage[]; streaming_behavior?: StreamingBehavior }
  | { type: "models_list"; in_reply_to: string; models: WireModel[]; current?: WireModel };
```

**Target State**:

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

**Implementation Notes**:

- Generate every current `ClientMessage`, `ServerMessage`, `SessionHistoryEvent`, `WireImage`, `Usage`, `WireModel`, `ThinkingLevel`, `StreamingBehavior`, `ByeReason`, `PairErrorCode`, `KnownErrorCode`, and open `ErrorCode` shape.
- Keep output in `generated/` and test it against the handwritten exports before switching imports.
- Preserve TypeScript ESM/NodeNext requirements; generated relative imports use `.js` if split across files.
- Avoid broad generated dependency imports in non-protocol modules.

**Acceptance Criteria**:

- [ ] Generated TS unions cover every variant currently in `types.ts`.
- [ ] Generated optional fields match the compatibility wire.
- [ ] `tsc --noEmit` compiles generated output under the pi-extension TS config.
- [ ] No production import is switched yet.

**Rollback**: remove generated TS output and tests; the hand-authored `types.ts` remains live.

---

### Step 3: Generate schema-derived registries and compatibility validators

**Priority**: High  
**Risk**: Medium  
**Source Lens**: codec drift / fail-fast boundary  
**Files**: `pi-extension/src/protocol/generated/protocol.generated.ts`, `pi-extension/src/protocol/generated/validators.generated.ts`, `pi-extension/src/protocol/generated/validators.generated.test.ts`, `protocol/schema/app-pi-*.schema.json`  
**Story**: `epic-bold-generated-protocol-ts-codegen-step-3`

**Current State**:

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

**Target State**:

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

**Implementation Notes**:

- Generate `CLIENT_MESSAGE_TYPES`, `SERVER_MESSAGE_TYPES`, and nested history-event registries from the schema/IR.
- Generate self-contained predicate validators for the compatibility profile. Open pockets remain open: tool `args`, tool `result`, unknown `ErrorCode`, and future-tolerant extra properties where the schema marks them open.
- Add tests that assert the drifted server variants appear in the generated registry.
- Keep canonical-session-only requirements as metadata until that feature enables the stricter profile.

**Acceptance Criteria**:

- [ ] Generated server registry includes `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list`.
- [ ] Generated validators accept representative current fixtures for all client/server variants.
- [ ] Generated validators reject malformed objects with missing `type` or wrong required-field types.
- [ ] No handwritten message-type allowlist remains in generated code.

**Rollback**: remove generated validator/registry output and tests; Step 2 type generation can remain side-by-side.

---

### Step 4: Replace `types.ts` and `codec.ts` with generated facades and validator-backed codecs

**Priority**: High  
**Risk**: High  
**Source Lens**: generated contracts / dead-weight removal / fail-fast boundary  
**Files**: `pi-extension/src/protocol/types.ts`, `pi-extension/src/protocol/codec.ts`, `pi-extension/src/transport/peer_channel.ts`, `pi-extension/src/index.ts`, `pi-extension/src/protocol/codec.test.ts`  
**Story**: `epic-bold-generated-protocol-ts-codegen-step-4`

**Current State**:

```ts
// pi-extension/src/protocol/codec.ts
export function decodeServer(line: string): ServerMessage {
  const obj = JSON.parse(line.trim());
  const t = (obj as Record<string, unknown>).type as string;
  if (!SERVER_TYPES.has(t as ServerMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${t}`);
  }
  return obj as ServerMessage;
}
```

```ts
// pi-extension/src/transport/peer_channel.ts
this.onMessage(msg as ClientMessage);
```

**Target State**:

```ts
// pi-extension/src/protocol/types.ts
export type {
  ActionName,
  ByeReason,
  ClientMessage,
  ErrorCode,
  KnownErrorCode,
  PairErrorCode,
  ServerMessage,
  SessionHistoryEvent,
  StreamingBehavior,
  ThinkingLevel,
  Usage,
  WireImage,
  WireModel,
} from "./generated/protocol.generated.js";
```

```ts
// pi-extension/src/protocol/codec.ts
import {
  CLIENT_MESSAGE_TYPES,
  SERVER_MESSAGE_TYPES,
  isClientMessage,
  isServerMessage,
} from "./generated/protocol.generated.js";

export function decodeServer(line: string): ServerMessage {
  const obj = parseJsonLine(line);
  const type = readType(obj);
  if (!SERVER_MESSAGE_TYPES.includes(type as ServerMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${type}`);
  }
  if (!isServerMessage(obj)) {
    throw new DecodeError("invalid_message", `invalid server message: ${type}`);
  }
  return obj;
}

export function decodeClient(line: string): ClientMessage {
  const obj = parseJsonLine(line);
  const type = readType(obj);
  if (!CLIENT_MESSAGE_TYPES.includes(type as ClientMessage["type"])) {
    throw new DecodeError("unsupported_type", `unknown type: ${type}`);
  }
  if (!isClientMessage(obj)) {
    throw new DecodeError("invalid_message", `invalid client message: ${type}`);
  }
  return obj;
}
```

**Implementation Notes**:

- Keep `types.ts` as the stable import facade so call sites do not churn.
- Keep `encodeClient` and `decodeServer` APIs; add `decodeClient` for inbound app messages.
- Use `decodeClient` in `PlainPeerChannel._onLine` and `_installAutoListener` instead of parse-and-cast. Invalid/malformed app messages remain dropped at the boundary; valid current messages continue to route.
- Update `codec.test.ts` so server/client fixture expectations derive from generated registries, not a second handwritten file allowlist.
- Preserve JSONL newline behavior in `encodeClient`.

**Acceptance Criteria**:

- [ ] `types.ts` no longer hand-authors protocol unions; it re-exports generated types.
- [ ] `codec.ts` no longer contains a handwritten `SERVER_TYPES` registry.
- [ ] `decodeServer` accepts schema-valid `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list` payloads.
- [ ] App-origin relay messages pass through generated `decodeClient` before routing.
- [ ] `corepack pnpm typecheck` and `corepack pnpm test` pass from `pi-extension/`.

**Rollback**: revert the facade/codec/boundary-adoption commit to restore handwritten `types.ts`, `codec.ts`, and parse-and-cast routing.

---

### Step 5: Add TS generated-protocol parity checks and package scripts

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: contract-test gap / generated contract drift  
**Files**: `pi-extension/package.json`, `pi-extension/src/protocol/generated/*.ts`, `pi-extension/src/protocol/generated/*.test.ts`, `protocol/schema/manifest.json`, `tools/protocol-codegen/`  
**Story**: `epic-bold-generated-protocol-ts-codegen-step-5`

**Current State**:

```json
{
  "scripts": {
    "build": "tsc",
    "typecheck": "tsc --noEmit",
    "test": "vitest run"
  }
}
```

**Target State**:

```json
{
  "scripts": {
    "generate:protocol": "tsx ../tools/protocol-codegen/src/index.ts --target ts --out src/protocol/generated/protocol.generated.ts",
    "check:protocol": "pnpm generate:protocol --check",
    "typecheck": "tsc --noEmit",
    "test": "vitest run"
  }
}
```

```ts
// Generated parity test shape.
expect(SERVER_MESSAGE_TYPES).toContain("models_list");
expect(new Set(SERVER_MESSAGE_TYPES)).toEqual(schemaServerTypeSet);
```

**Implementation Notes**:

- Add a check mode that fails when generated TS output is stale relative to `protocol/schema/manifest.json` and family schemas.
- Keep generated source committed because `pi-extension/` publishes from `src -> dist` and consumers should not need the generator at runtime.
- Keep `.orchestration/contracts/` only as legacy fixtures until the full generated-protocol epic replaces it.
- Record any schema incompleteness as an implementation note in this feature body rather than weakening tests.

**Acceptance Criteria**:

- [ ] `corepack pnpm --dir pi-extension check:protocol` fails on stale generated output.
- [ ] Type registry parity is derived from schema/IR, not a handwritten test allowlist.
- [ ] `corepack pnpm --dir pi-extension typecheck`, `test`, and `build` pass.
- [ ] No generated `dist/` or local build artifacts are committed.

**Rollback**: remove the package scripts and parity tests; generated runtime code from earlier steps remains controlled by normal typecheck/test until restored.

## Implementation Order

1. `epic-bold-generated-protocol-ts-codegen-step-1` — add the TS generator target and manifest/IR handoff after `epic-bold-generated-protocol-schema-source`.
2. `epic-bold-generated-protocol-ts-codegen-step-2` — emit TS unions/shared types beside the hand mirror.
3. `epic-bold-generated-protocol-ts-codegen-step-3` — emit registry and compatibility validators.
4. `epic-bold-generated-protocol-ts-codegen-step-4` — swap stable TS facades/codecs and route app-origin messages through generated `decodeClient`.
5. `epic-bold-generated-protocol-ts-codegen-step-5` — add stale-generation and schema parity checks.

## Atomic steps acknowledged

- Step 4 is the atomic runtime swap because `types.ts` is imported throughout `pi-extension/`; keep the public facade stable and revert the whole step if generated types or validators break call sites.
- The registry drift fix changes helper behavior for previously rejected but schema-valid server messages. This is accepted as the purpose of the refactor and does not change the wire shape.
- Canonical-session strictness is intentionally not atomic here. The TS generator must carry profile metadata but stay on the compatibility profile until the canonical-session epic enables required `session_id` enforcement.

## Other agent review

- Invoked because: delegated autopilot design for a bold refactor feature.
- Scope: skipped; this nested worker has no subagent/peer tool exposed. The requested raised-tier sub-delegation could not be performed from this harness, so direct-read evidence and sibling designs were used instead.
- Accepted: align TS with the Dart feature's custom deterministic schema/IR generator rather than direct TS-only JSON Schema generation, because parity and patchbay portability matter more than one-language convenience.


## Review — advanced to done (2026-06-30)

All 5 child steps `done` (generator target/spike → generated unions/value-types →
registries/validators → atomic runtime facade+codec swap → parity checks + package
scripts). The pi-extension TypeScript protocol is now generated from
`protocol/schema/manifest.json` through the shared codegen IR: `types.ts` re-exports
generated types, `codec.ts` uses generated registries/validators + `decodeClient`, and
`check:protocol` guards against stale generated output. Epic complete.
