---
id: epic-bold-generated-protocol-schema-source-step-4
kind: story
stage: implementing
tags: [refactor, bold, cockpit, pi-extension]
parent: epic-bold-generated-protocol-schema-source
depends_on: [epic-bold-generated-protocol-schema-source-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Add the cockpit control RPC schema namespace

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / naming inconsistency  
**Files**: `protocol/schema/cockpit-control.schema.json`, `protocol/fixtures/cockpit/*.jsonl`, `pi-extension/src/index.ts` (read-only reference), `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart` (read-only reference), `cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart` (read-only reference)

## Current State

Cockpit↔pi control is a fourth transport with duplicated magic strings:

```ts
// pi-extension/src/index.ts
export const CTRL_PREFIX = "\x00remote-pi-ctrl:";

export async function _handleControl(cmd: string): Promise<void> {
  if (cmd.startsWith("rename:")) return _renameAgent(cmd.slice("rename:".length).trim());
  switch (cmd) {
    case "relay:on":
    case "relay:off":
    case "relay:toggle":
    case "relay:status":
      // toggles relay and emits remote-pi:relay-state
  }
}
```

```dart
// cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart
static const _ctrlPrefix = '\x00remote-pi-ctrl:';

await _writeLine(
  '${jsonEncode(<String, dynamic>{'type': 'prompt', 'message': '$_ctrlPrefix$verb'})}\n',
);
```

Cockpit then parses custom Pi messages by string:

```dart
// cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart
switch (customType) {
  case 'remote-pi:relay-state':
    return RpcRelayState(...);
  case 'remote-pi:name-assigned':
    return RpcNameAssigned(...);
  default:
    return RpcUnknown('message_start:custom:${customType ?? "?"}');
}
```

## Target State

Model the current compatibility encoding and the target structured command/event vocabulary in the same canonical schema. The sibling `epic-bold-generated-protocol-cockpit-control-rpc` will replace the magic prefix; this step only creates the schema source.

```json
{
  "$id": "https://remote-pi.dev/schemas/cockpit-control.schema.json",
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
      },
      "additionalProperties": false,
      "x-remote-pi": { "transport": "pi-custom-event" }
    },
    "relayStateEvent": {
      "type": "object",
      "required": ["customType", "details"],
      "properties": {
        "customType": { "const": "remote-pi:relay-state" },
        "details": {
          "type": "object",
          "required": ["status", "connected"],
          "properties": {
            "status": { "enum": ["connected", "reconnecting", "disconnected"] },
            "connected": { "type": "boolean" }
          },
          "additionalProperties": false
        }
      }
    },
    "nameAssignedEvent": {
      "type": "object",
      "required": ["customType", "details"],
      "properties": {
        "customType": { "const": "remote-pi:name-assigned" },
        "details": {
          "type": "object",
          "required": ["assigned", "changed"],
          "properties": { "assigned": { "type": "string" }, "changed": { "type": "boolean" } },
          "additionalProperties": false
        }
      }
    }
  }
}
```

## Implementation Notes

- Treat this as a transport-spanning schema namespace, not as app-pi relay traffic. It belongs in the same manifest because the TS/Dart generators need the same vocabulary source.
- Include compatibility fixture lines for `\u0000remote-pi-ctrl:relay:status` prompt payloads and custom event payloads (`remote-pi:relay-state`, `remote-pi:name-assigned`, `remote-pi:pair-code`, `remote-pi:paired`, `remote-pi:mesh-revoked`).
- Do not require the sibling implementation to keep the NUL prefix; the schema should make the current encoding explicit so it can be replaced safely.
- Keep actual process request/response RPC (`get_state`, `set_model`, etc.) out of this step unless it is already part of Remote Pi-specific custom control. The target is the Remote Pi control overlay, not the full Pi RPC protocol.

## Acceptance Criteria

- [ ] Cockpit control verbs and Remote Pi custom event strings are represented in `cockpit-control.schema.json`.
- [ ] The schema documents the current NUL-prefixed prompt compatibility encoding and the target structured command object.
- [ ] Fixtures cover relay control, rename, relay-state, name-assigned, pair-code, paired, and mesh-revoked custom events.
- [ ] No `pi-extension` or `cockpit` runtime code is changed in this step.

## Rollback

Revert `cockpit-control.schema.json` and cockpit fixtures. Runtime behavior remains unchanged because the schema is side-by-side until the sibling migration consumes it.
