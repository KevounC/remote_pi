---
id: epic-bold-generated-protocol-cockpit-control-rpc-step-3
kind: story
stage: implementing
tags: [refactor, bold, cockpit]
parent: epic-bold-generated-protocol-cockpit-control-rpc
depends_on: [epic-bold-generated-protocol-cockpit-control-rpc-step-2]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 3: Emit schema-compatible control commands from Cockpit and align custom-event parsing with protocol map

**Priority**: Medium  
**Risk**: Medium  
**Source Lens**: codegen boundary / generated contract  
**Files**: `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart`, `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart`, `cockpit/docs/rpc-protocol.md`, `cockpit/lib/app/cockpit/ui/session/agent_session.dart`

## Current State

Cockpit control sender still hardcodes a NUL-prefixed prompt message:

```dart
await _writeLine(jsonEncode({
  'type': 'prompt',
  'message': '$_ctrlPrefix$verb',
}));
```

Event parsing handles only `relay-state` and `name-assigned`, leaving schema
neighbors (`pair-code`, `paired`, `mesh-revoked`) as unknown even when they are
live protocol messages in extension flows.

## Target State

- Replace prompt payload construction with schema command serialization so Cockpit sends
  explicit control command envelopes over the same `prompt` transport.
- Keep compatibility shim path in place if required by schema/source generation state.
- Expand Cockpit event mapping to parse all current cockpit-overlay custom events in
  one schema-backed switch.
- Keep UI state transitions tied to the same typed `RpcRelayState`/`RpcNameAssigned`
  entities (relay status updates and rename updates remain unchanged).

## Implementation Notes

- `_ctrlPrefix` becomes compatibility-only on the receiving extension side; Cockpit
  should not need it as primary wire format when schema command framing is active.
- Add/adjust any schema-protocol comments in docs to avoid drift with the new
  encoding rationale.
- This step should be blocked from introducing any `ui` behavior changes not already
  present in `agent_session.dart` (sendControl is transport-only).

## Acceptance Criteria

- [ ] Control commands from Cockpit are emitted as schema command envelopes.
- [ ] Custom overlay events used by relay/pairing flows are all recognized in the
  adapter map.
- [ ] Existing relay and pairing UX behavior is preserved.
- [ ] Test fixture/docs are updated so protocol validation references include the
  schema-controlled control overlay.

## Rollback

Revert Cockpit control sender to legacy `_ctrlPrefix + verb` formatting and
retain only the two current custom event handlers; restore prior docs if parser
coverage changed.
