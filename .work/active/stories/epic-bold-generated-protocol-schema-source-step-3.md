---
id: epic-bold-generated-protocol-schema-source-step-3
kind: story
stage: implementing
tags: [refactor, bold, relay, pi-extension, app]
parent: epic-bold-generated-protocol-schema-source
depends_on: [epic-bold-generated-protocol-schema-source-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Port relay-owned outer, control, room, and cross-PC frames

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / pattern drift  
**Files**: `protocol/schema/relay-outer.schema.json`, `protocol/schema/relay-control.schema.json`, `protocol/schema/cross-pc.schema.json`, `protocol/schema/defs/agent-envelope.schema.json`, `protocol/fixtures/relay/*.jsonl`, `protocol/fixtures/cross-pc/*.jsonl`

## Current State

Relay-owned schemas are handwritten in Rust and manually parsed in handlers:

```rust
// relay/src/protocol/outer.rs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String,
}

// relay/src/rooms.rs
#[derive(Debug, Clone, serde::Serialize)]
pub struct RoomMeta {
    pub room_id: String,
    pub name: Option<String>,
    pub cwd: Option<String>,
    pub model: Option<String>,
    pub thinking: Option<String>,
    pub working: bool,
    pub started_at: i64,
}

pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub working: Option<bool>,
}
```

`relay/src/handlers/peer.rs` parses `hello.room_meta`, presence, room subscriptions, `room_meta_update`, and `pi_envelope` frames through ad-hoc `serde_json::Value` checks. The relay forwards the inner app-pi payload opaquely and must keep doing so.

## Target State

Add relay-owned schemas without making the relay parse app-pi inner messages. Model `ct` and `envelope.body` as opaque JSON payloads at the relay boundary.

```json
{
  "$id": "https://remote-pi.dev/schemas/relay-outer.schema.json",
  "$defs": {
    "outerEnvelope": {
      "type": "object",
      "required": ["peer", "ct"],
      "properties": {
        "peer": { "type": "string", "minLength": 1 },
        "room": { "type": "string", "default": "main" },
        "ct": { "type": "string", "contentEncoding": "base64" }
      },
      "additionalProperties": false,
      "x-remote-pi": { "relayOpaque": ["ct"], "maxDecodedBytesDefault": 4194304 }
    },
    "roomMeta": {
      "type": "object",
      "required": ["room_id", "working", "started_at"],
      "properties": {
        "room_id": { "type": "string", "minLength": 1 },
        "name": { "type": "string" },
        "cwd": { "type": "string" },
        "model": { "type": "string" },
        "thinking": { "type": "string" },
        "working": { "type": "boolean" },
        "started_at": { "type": "integer" }
      },
      "additionalProperties": false
    }
  }
}
```

```json
{
  "$id": "https://remote-pi.dev/schemas/cross-pc.schema.json",
  "$defs": {
    "agentEnvelope": {
      "type": "object",
      "required": ["from", "to", "id", "re", "body"],
      "properties": {
        "from": { "type": "string", "minLength": 1 },
        "to": { "oneOf": [{ "type": "string", "minLength": 1 }, { "type": "array", "minItems": 1, "items": { "type": "string", "minLength": 1 } }] },
        "id": { "$ref": "./defs/app-pi-common.schema.json#/$defs/uuid" },
        "re": { "oneOf": [{ "$ref": "./defs/app-pi-common.schema.json#/$defs/uuid" }, { "type": "null" }] },
        "body": true
      },
      "additionalProperties": false
    },
    "piEnvelope": {
      "type": "object",
      "required": ["type", "to_pc", "envelope"],
      "properties": { "type": { "const": "pi_envelope" }, "to_pc": { "type": "string", "minLength": 1 }, "envelope": { "$ref": "#/$defs/agentEnvelope" } }
    },
    "piEnvelopeIn": {
      "type": "object",
      "required": ["type", "from_pc", "envelope"],
      "properties": { "type": { "const": "pi_envelope_in" }, "from_pc": { "type": "string", "minLength": 1 }, "envelope": { "$ref": "#/$defs/agentEnvelope" } }
    }
  }
}
```

## Implementation Notes

- Keep relay/app-pi concerns separate: relay schemas cover auth/control/outer/cross-PC frames only; they do not require the relay to decode `ct` or inspect app-pi inner payloads.
- Model `room_meta_update.meta` patch semantics explicitly: `model` and `thinking` can be absent or string/null; `working` can be absent or boolean, never null.
- Capture the current 4 MiB decoded payload default from `relay/src/protocol/outer.rs` even where older docs still say 1 MiB.
- Add fixtures for `hello`, `auth`, `challenge`, `room_meta_update` with `model`, `thinking`, and `working`, `pi_envelope`, `pi_envelope_in`, and relay `transport_error` envelope shape.

## Acceptance Criteria

- [ ] `OuterEnvelope`, `RoomMeta`, `RoomMetaPatch`, auth frames, presence frames, rooms frames, and `room_meta_update` are represented in schema.
- [ ] `pi_envelope` / `pi_envelope_in` and the generic `{from,to,id,re,body}` agent envelope are represented in schema.
- [ ] The schema marks app-pi `ct` and agent `body` as opaque to relay routing.
- [ ] Added relay/cross-PC fixtures validate against the schema.
- [ ] No relay runtime parser is replaced in this step.

## Rollback

Revert the relay/cross-PC schema and fixtures. No runtime code consumes these schemas yet, so rollback is isolated to `protocol/`.
