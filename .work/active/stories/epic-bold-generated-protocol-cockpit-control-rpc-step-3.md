---
id: epic-bold-generated-protocol-cockpit-control-rpc-step-3
kind: story
stage: done
tags: [refactor, bold, cockpit]
parent: epic-bold-generated-protocol-cockpit-control-rpc
depends_on: [epic-bold-generated-protocol-cockpit-control-rpc-step-2]
release_binding: cockpit-v1.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] Control commands from Cockpit are emitted as schema command envelopes.
- [x] Custom overlay events used by relay/pairing flows are all recognized in the
  adapter map.
- [x] Existing relay and pairing UX behavior is preserved.
- [x] Test fixture/docs are updated so protocol validation references include the
  schema-controlled control overlay.

## Rollback

Revert Cockpit control sender to legacy `_ctrlPrefix + verb` formatting and
retain only the two current custom event handlers; restore prior docs if parser
coverage changed.

## Implementation

- Schema-envelope emission: `PiRpcProcess.sendControl` now writes a `prompt` frame whose `message` is a JSON `remote_pi_control` envelope (`relay_on/off/toggle/status`, `rename` with non-empty `name`), rather than the legacy NUL-prefixed verb string.
- Event-mapping alignment: `RpcControlOverlayEventType` remains the schema-backed custom-event registry; `RpcEventMapper` continues mapping `relay-state`, `name-assigned`, `pair-code`, `paired`, and `mesh-revoked`, and now rejects malformed `paired` details as `RpcUnknown` instead of creating a partial schema event.
- UX preservation: `agent_session.dart` behavior was left unchanged; relay-state still updates `relayStatus`, name-assigned still renames only when `changed`, and pair/paired/revoked session events remain typed-but-ignored by the session UI.
- Docs/tests: `cockpit/docs/rpc-protocol.md` documents the structured overlay on the `prompt` transport and the full custom-event map; added `cockpit/test/data/pi_rpc_process_control_test.dart` for schema-envelope serialization and updated mapper tests for schema-aligned event details.
- Verification: `PUB_CACHE=/home/agent/projects/remote_pi/.pub-cache /home/agent/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline` passed; `flutter analyze` passed with 0 issues; `flutter test` passed with 228/228 tests. A first full-suite run timed out at the harness limit after reaching 222 passing tests; the rerun completed green.
- Discrepancies from design: `cockpit/lib/app/cockpit/domain/entities/pi_command.dart` comments were updated to avoid stale NUL-prefix documentation; no UI behavior changes were needed in `agent_session.dart`.

## Review

Approved (2026-06-30). Independently re-ran: **cockpit tests 228 passed (up from 226
— the agent's new schema-envelope serialization + mapper tests)**; `flutter analyze`
clean. Commit `6649528` scoped to cockpit only (pi_rpc_process + rpc_event_mapper +
rpc_event + docs + tests); collision guard held (app/pi-ext disjoint).

Schema-envelope emission verified: `PiRpcProcess.sendControl` now writes a `prompt`
frame whose `message` is a JSON `remote_pi_control` envelope (relay_on/off/toggle/
status, rename), not the legacy NUL-prefixed verb string. Event-mapping aligned:
`relay-state`/`name-assigned`/`pair-code`/`paired`/`mesh-revoked` all covered through
the typed `RpcControlOverlayEventType` registry; malformed `paired` now rejected as
`RpcUnknown` (fail-fast) instead of partial schema event. UX preserved (agent_session
unchanged). Docs updated in `cockpit/docs/rpc-protocol.md`.
