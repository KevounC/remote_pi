---
id: epic-bold-generated-protocol-schema-source
kind: feature
stage: review
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-generated-protocol
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Generated protocol — canonical schema source

## Brief
The single canonical schema + validators: the one place a new wire message is
added. Covers all three transports (app↔pi chat/control, cross-PC
`pi_envelope`, cockpit↔pi control RPC). Every message is self-describing —
carries canonical session id, turn id, type — so no "1 pairing = 1 session"
assumption and no legacy-no-room fail-open path survives.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: the source the three codegen targets (Dart, TS, Rust) generate
  from. Parallel to the riskiest child — the schema can be defined while the
  Dart codegen feasibility is proven.

## Foundation references
- Evidence of current fragmentation: `pi-extension/src/protocol/types.ts`,
  `app/lib/protocol/protocol.dart`, `relay/src/protocol/outer.rs`,
  `relay/src/rooms.rs`, `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:372-385`.

<!-- /agile-workflow:refactor-design picks the schema language (JSON Schema /
Protobuf / TS-as-source) and validator approach. -->

## Design decisions

- **Schema language chosen: JSON Schema 2020-12 + a small `x-remote-pi` manifest.** This is the least-surprising source for Remote Pi's actual JSONL wire, gives fail-fast validators at JSON boundaries, and can feed TS/Dart/Rust generators without making one runtime language the canonical source. TypeScript-native libraries may be emitted or used by generated targets, but the source is neutral JSON Schema files under `protocol/schema/`.
- **Rejected: Protobuf/Buf as the immediate source.** Buf is attractive for a future rigorous/patchbay rewrite because it gives strong linting and breaking-change checks, but default Protobuf JSON mapping fights the existing `{type: ...}` discriminated JSON shape, Dart protoc emits message classes rather than the clean sealed unions this epic wants, and runtime validators would still need a custom JSON bridge. Choosing Protobuf now would move risk into custom plugins before the existing JSON wire is under control.
- **Rejected: TypeScript-native schema as the source (`zod`, TypeBox, Valibot).** TS-native definitions would make TS pleasant and the repo already carries `zod` and `typebox`, but TS-as-source would keep Dart/Rust as downstream mirrors unless we first generate neutral JSON Schema and discipline every non-TS feature to consume that derivative. That recreates the source/derivative ambiguity this refactor is meant to remove.
- **Rejected: custom IDL.** A bespoke discriminated-message DSL would fit Remote Pi perfectly, but it would be a new protocol language to maintain and would travel worse to patchbay than JSON Schema or Buf.
- **Behavior-preservation judgment.** Although the epic target is self-describing canonical session/turn fields, this refactor-design keeps schema-source side-by-side and behavior-preserving. The schema should validate today's compatibility wire and also carry `canonical-session` profile metadata for future required `session_id`/`turn_id` enforcement. The later canonical-session epic flips enforcement deliberately; schema-source does not silently change the live wire.
- **Relay responsibility boundary.** The relay's app-pi payload remains opaque. Schema-source covers relay-owned outer/control/cross-PC frames, but it does not imply the relay should parse inner chat/control bodies.
- **Dispatch rationale.** Direct-read only. The feature target is a bounded protocol/schema design with clear source files; no sub-agent tool was available in this delegated sub-agent harness, so no advisory subagent was spawned. The grounding pass read foundation docs, rules, current TS/Dart/Rust/cockpit mirrors, and fixtures directly.
- **Cycle check.** New stories form a linear chain: step 1 has no dependencies; each later story depends only on the immediately previous story. The parent feature has `depends_on: []`, and no new story depends on the parent or a later sibling, so no frontmatter cycle is introduced.

## Refactor Overview

The current protocol contract is scattered across `pi-extension/src/protocol/types.ts`, `pi-extension/src/protocol/codec.ts`, `app/lib/protocol/protocol.dart`, `relay/src/protocol/outer.rs`, `relay/src/rooms.rs`, `.orchestration/contracts/`, and the cockpit NUL-prefix control path. The high-value refactor is to introduce one neutral schema package first, still side-by-side with the handwritten mirrors, then let sibling codegen features consume it.

The schema source should cover five families:

1. app↔pi inner `ClientMessage` / `ServerMessage` / `SessionHistoryEvent` JSON;
2. relay outer envelope and relay control frames;
3. cross-PC `pi_envelope` / `pi_envelope_in` and generic agent envelope;
4. cockpit Remote Pi control overlay over Pi custom events;
5. fixture validation and a deterministic type catalog for TS/Dart/Rust codegen stories.

## Refactor Steps

### Step 1: Establish the canonical schema package and manifest

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / generated contracts  
**Files**: `protocol/package.json`, `protocol/README.md`, `protocol/schema/remote-pi.schema.json`, `protocol/schema/manifest.json`, `protocol/schema/defs/*.schema.json`  
**Story**: `epic-bold-generated-protocol-schema-source-step-1`

**Current State**:

```ts
// pi-extension/src/protocol/codec.ts
const SERVER_TYPES = new Set<ServerMessage["type"]>([
  "pair_ok", "pair_error", "user_input", "queued_message_state",
  "agent_chunk", "agent_done", "agent_message", "tool_request",
  "tool_result", "error", "cancelled", "pong", "bye", "session_history",
]);
```

The registry omits several live `ServerMessage` variants and is not generated from the union it claims to protect.

**Target State**:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://remote-pi.dev/schemas/remote-pi.schema.json",
  "$defs": {
    "uuid": { "type": "string", "format": "uuid" },
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

**Implementation Notes**:

- Create a repo-root `protocol/` package because the schema is cross-subproject code, not a pi-extension-only artifact.
- Keep JSON Schema as the committed source; put generator hints in `x-remote-pi`.
- Do not switch runtime consumers in this step.

**Acceptance Criteria**:

- [ ] Canonical schema package exists at `protocol/`.
- [ ] Manifest enumerates app-pi client/server, relay control, cross-PC, and cockpit control families.
- [ ] Schema source is language-neutral JSON Schema 2020-12.
- [ ] Runtime behavior is unchanged.

**Rollback**: delete the new `protocol/` package; no runtime consumer rollback required.

---

### Step 2: Port the app↔pi inner message families into the schema

**Priority**: High  
**Risk**: Medium  
**Source Lens**: single source of truth / generated contracts  
**Files**: `protocol/schema/app-pi-client.schema.json`, `protocol/schema/app-pi-server.schema.json`, `protocol/schema/defs/app-pi-common.schema.json`, `protocol/fixtures/app-pi/*.jsonl`  
**Story**: `epic-bold-generated-protocol-schema-source-step-2`

**Current State**:

```ts
// pi-extension/src/protocol/types.ts
export type ClientMessage =
  | { type: "pair_request"; id: string; token: string; device_name: string }
  | { type: "user_message"; id: string; text: string; images?: WireImage[]; streaming_behavior?: StreamingBehavior }
  | { type: "queued_message_set"; id: string; text: string }
  | { type: "queued_message_clear"; id: string }
  | { type: "approve_tool"; id: string; tool_call_id: string; decision: "allow" | "deny" }
  | { type: "cancel"; id: string; target_id: string }
  | { type: "ping"; id: string }
  | { type: "session_sync"; id: string; limit?: number }
  | { type: "session_new"; id: string }
  | { type: "session_compact"; id: string }
  | { type: "model_set"; id: string; provider: string; model_id: string }
  | { type: "thinking_set"; id: string; level: ThinkingLevel }
  | { type: "list_models"; id: string };
```

**Target State**:

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
  ]
}
```

**Implementation Notes**:

- Port from `types.ts`, then cross-check `app/lib/protocol/protocol.dart` and existing fixtures.
- Add fixture coverage for current messages missing from `.orchestration/contracts/`.
- Preserve open fields only where the protocol is intentionally open (`ErrorCode`, tool args/results, unknown result values).
- Use `x-remote-pi.profileRequired.canonical-session` to mark future `session_id` / `turn_id` requirements without changing the compatibility profile.

**Acceptance Criteria**:

- [ ] Every `ClientMessage` and `ServerMessage` variant from `types.ts` has one schema definition.
- [ ] Every `SessionHistoryEvent` variant has one schema definition.
- [ ] Existing and newly-added app-pi fixtures validate.
- [ ] `user_message`, `compaction`, `action_ok`, `action_error`, and `models_list` are covered so the current `SERVER_TYPES` drift class cannot recur.

**Rollback**: revert app-pi schema files and app-pi fixtures; no runtime consumer rollback required.

---

### Step 3: Port relay-owned outer, control, room, and cross-PC frames

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / pattern drift  
**Files**: `protocol/schema/relay-outer.schema.json`, `protocol/schema/relay-control.schema.json`, `protocol/schema/cross-pc.schema.json`, `protocol/schema/defs/agent-envelope.schema.json`, `protocol/fixtures/relay/*.jsonl`, `protocol/fixtures/cross-pc/*.jsonl`  
**Story**: `epic-bold-generated-protocol-schema-source-step-3`

**Current State**:

```rust
// relay/src/protocol/outer.rs
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String,
}

// relay/src/rooms.rs
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub working: Option<bool>,
}
```

**Target State**:

```json
{
  "$defs": {
    "outerEnvelope": {
      "type": "object",
      "required": ["peer", "ct"],
      "properties": {
        "peer": { "type": "string", "minLength": 1 },
        "room": { "type": "string", "default": "main" },
        "ct": { "type": "string", "contentEncoding": "base64" }
      },
      "x-remote-pi": { "relayOpaque": ["ct"], "maxDecodedBytesDefault": 4194304 }
    },
    "piEnvelope": {
      "type": "object",
      "required": ["type", "to_pc", "envelope"],
      "properties": {
        "type": { "const": "pi_envelope" },
        "to_pc": { "type": "string", "minLength": 1 },
        "envelope": { "$ref": "./defs/agent-envelope.schema.json#/$defs/agentEnvelope" }
      }
    }
  }
}
```

**Implementation Notes**:

- Keep the relay's inner app-pi payload opaque; do not imply the relay parses `ct`.
- Schema `room_meta_update.meta` merge-patch semantics: absent preserves; `model`/`thinking` may be explicit null; `working` is absent or boolean only.
- Capture the implemented 4 MiB decoded `ct` default, even where older docs still say 1 MiB.

**Acceptance Criteria**:

- [ ] `OuterEnvelope`, auth/control frames, presence/rooms frames, `RoomMeta`, `RoomMetaPatch`, and cross-PC frames are represented.
- [ ] Relay opaque payload boundaries are explicit.
- [ ] Relay and cross-PC fixtures validate.
- [ ] Relay runtime parser is unchanged.

**Rollback**: revert relay/cross-PC schema files and fixtures; no runtime consumer rollback required.

---

### Step 4: Add the cockpit control RPC schema namespace

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / naming inconsistency  
**Files**: `protocol/schema/cockpit-control.schema.json`, `protocol/fixtures/cockpit/*.jsonl`, read-only references in `pi-extension/src/index.ts` and `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart`  
**Story**: `epic-bold-generated-protocol-schema-source-step-4`

**Current State**:

```ts
// pi-extension/src/index.ts
export const CTRL_PREFIX = "\x00remote-pi-ctrl:";
```

```dart
// cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart
static const _ctrlPrefix = '\x00remote-pi-ctrl:';
await _writeLine('${jsonEncode(<String, dynamic>{'type': 'prompt', 'message': '$_ctrlPrefix$verb'})}\n');
```

**Target State**:

```json
{
  "$defs": {
    "controlVerb": {
      "oneOf": [
        { "const": "relay:on" },
        { "const": "relay:off" },
        { "const": "relay:toggle" },
        { "const": "relay:status" },
        { "type": "string", "pattern": "^rename:.+" }
      ],
      "x-remote-pi": { "compatEncoding": "nul-prefixed-prompt", "prefix": "\\u0000remote-pi-ctrl:" }
    },
    "controlCommand": {
      "type": "object",
      "required": ["type", "command"],
      "properties": {
        "type": { "const": "remote_pi_control" },
        "command": { "enum": ["relay_on", "relay_off", "relay_toggle", "relay_status", "rename"] },
        "name": { "type": "string", "minLength": 1 }
      }
    }
  }
}
```

**Implementation Notes**:

- The schema spans the custom-event transport but does not replace it yet.
- Include both compatibility strings and target structured commands/events so the sibling cockpit-control-rpc feature can retire the prefix without inventing a new vocabulary.
- Keep full Pi RPC request/response (`get_state`, `set_model`, etc.) out unless it is Remote Pi-specific custom control.

**Acceptance Criteria**:

- [ ] Relay control verbs, rename, and Remote Pi custom event payloads are schema-defined.
- [ ] The current NUL-prefix encoding is explicit as compatibility metadata.
- [ ] Cockpit fixtures validate.
- [ ] No cockpit or extension runtime code is changed.

**Rollback**: revert cockpit-control schema and fixtures; no runtime consumer rollback required.

---

### Step 5: Add schema validation checks and generator handoff contracts

**Priority**: High  
**Risk**: Low  
**Source Lens**: generated contracts / fail fast  
**Files**: `protocol/package.json`, `protocol/scripts/check-fixtures.ts`, `protocol/scripts/list-types.ts`, `protocol/fixtures/**`, `protocol/README.md`  
**Story**: `epic-bold-generated-protocol-schema-source-step-5`

**Current State**:

```md
# .orchestration/contracts/protocol.md
Fixtures folder carries 1 example JSONL per `type`.
```

The fixture set is useful but no longer complete and is not generated from the actual source.

**Target State**:

```json
{
  "name": "@remote-pi/protocol-schema",
  "private": true,
  "type": "module",
  "scripts": {
    "check": "tsx scripts/check-fixtures.ts",
    "list-types": "tsx scripts/list-types.ts"
  },
  "devDependencies": {
    "ajv": "^8.17.0",
    "ajv-formats": "^3.0.0",
    "tsx": "^4.22.0",
    "typescript": "^6.0.3"
  }
}
```

**Implementation Notes**:

- `check-fixtures.ts` compiles schemas and validates every JSONL object in `protocol/fixtures/<family>/*.jsonl`.
- `list-types.ts` emits a deterministic catalog used by sibling TS/Dart/Rust generator stories.
- Keep `.orchestration/contracts/` as legacy reference until generated consumers retire it; do not delete it in schema-source.

**Acceptance Criteria**:

- [ ] `corepack pnpm --dir protocol check` validates all schema fixtures.
- [ ] `corepack pnpm --dir protocol list-types` emits every manifest message type deterministically.
- [ ] The check catches missing-type registry drift like the current `codec.ts` omission.
- [ ] README documents how sibling generators consume the manifest.

**Rollback**: remove validation scripts/package metadata/fixtures. Static schema files can remain if earlier steps are still useful.

## Implementation Order

1. `epic-bold-generated-protocol-schema-source-step-1`
2. `epic-bold-generated-protocol-schema-source-step-2`
3. `epic-bold-generated-protocol-schema-source-step-3`
4. `epic-bold-generated-protocol-schema-source-step-4`
5. `epic-bold-generated-protocol-schema-source-step-5`

All five steps are buildable and reviewable in isolation because they add side-by-side schema/fixture/check artifacts before any runtime consumer swaps to generated code.

## Implementation summary — wave 4

Stories now ready for review:

- `epic-bold-generated-protocol-schema-source-step-1` — done before this run.
- `epic-bold-generated-protocol-schema-source-step-2` — done before this run.
- `epic-bold-generated-protocol-schema-source-step-3` — advanced to review in this run; relay outer/control/rooms/presence/cross-PC schemas and fixtures added.
- `epic-bold-generated-protocol-schema-source-step-4` — advanced to review in this run; cockpit control compatibility/target schema and fixtures added.
- `epic-bold-generated-protocol-schema-source-step-5` — advanced to review in this run; AJV fixture checker and deterministic type catalog added.

Verification in this run: Python parsed all `protocol/**/*.json` and `protocol/**/*.jsonl`; `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store check` passed; `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store list-types` emitted 58 valid JSON catalog entries. Runtime consumers remain unchanged.

## Atomic steps acknowledged

- Step 1 locks the schema-language direction for downstream codegen. Rollback is mechanically simple but strategically high-impact, so the implementation should commit the decision in `protocol/README.md`.
- Future enforcement of canonical `session_id`/`turn_id` is intentionally not atomic here. This design records it as profile metadata and leaves live enforcement to the canonical-session epic to avoid a hidden behavior change.

