---
id: epic-bold-generated-protocol-cockpit-control-rpc-step-1
kind: story
stage: done
tags: [refactor, bold, cockpit, pi-extension]
parent: epic-bold-generated-protocol-cockpit-control-rpc
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 1: Add schema-aligned cockpit control command types and event entities in Cockpit

**Priority**: High  
**Risk**: Medium  
**Source Lens**: generated contract / missing abstraction  
**Files**: `cockpit/lib/app/cockpit/domain/contracts/rpc_process_gateway.dart`, `cockpit/lib/app/cockpit/domain/entities/rpc_event.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_data_mapper.dart`, `cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart`, `cockpit/lib/app/cockpit/domain/entities/pi_command.dart`

## Current State

Cockpit’s control surface is typed as opaque strings at the domain edge:

```dart
// rpc_process_gateway.dart
Future<Result<void, RpcError>> sendControl(String verb);

// rpc_event.dart and rpc_event_mapper.dart
case 'remote-pi:relay-state': ... RpcRelayState
case 'remote-pi:name-assigned': ... RpcNameAssigned
default: RpcUnknown('message_start:custom:...')
```

`pi_rpc_process.dart` writes `$_ctrlPrefix$verb` directly to a `prompt` frame,
and the adapter only recognizes two custom event cases (`relay-state`, `name-assigned`).

## Target State

- Add a generated-schema-aligned control command model under Cockpit domain (enum or
  sealed value class) that captures canonical control verbs and rename arguments.
- Use that model in `RpcProcessGateway.sendControl` (interface contract), while
  still keeping transport serialization centralized in the gateway impl.
- Expand typed `RpcEvent` to hold control overlay events from the same schema family,
  including:
  - relay-state
  - name-assigned
  - pair-code
  - paired
  - mesh-revoked
- Keep unknown custom event types as `RpcUnknown` to preserve failure isolation.

## Implementation Notes

- This is the first domain boundary step: schema family details belong in
  `pi_rpc_process.dart`/`_fromCustomMessage`, while UI/domain consume typed
  entities.
- Keep compatibility fields (`connected`, `assigned`, optional `name`, `peerId`, etc.)
  as-is so the existing UI flow does not change.
- The goal is a typed abstraction over the overlay, not a behavior change.

## Acceptance Criteria

- [ ] `RpcProcessGateway.sendControl` takes a schema command value (or command
  request object) instead of untyped raw verb text.
- [ ] A new/updated typed event set exists for current `remote-pi:*` overlay events.
- [ ] Event mapping still handles existing payloads without runtime format changes.
- [ ] No runtime behavior changes in relay control outcomes.
- [ ] Unknown custom event types continue to degrade safely as `RpcUnknown`.

## Rollback

Revert the Cockpit domain and adapter typed layer additions and restore the
string-only `sendControl(String)` contract and current event mapping; no protocol
runtime codepaths outside Cockpit are touched by this step.

## Implementation

- Added a schema-aligned `PiControlCommand` domain value in `pi_command.dart` and changed `RpcProcessGateway.sendControl` plus Cockpit callers/fakes to pass typed commands instead of raw relay/rename verb strings.
- Kept the runtime control transport behavior unchanged: `PiRpcProcess` still serializes commands to the existing NUL-prefixed `prompt` compatibility frame, centralized in the gateway adapter.
- Expanded the typed control-overlay event set and mapper for `remote-pi:relay-state`, `remote-pi:name-assigned`, `remote-pi:pair-code`, `remote-pi:paired`, and `remote-pi:mesh-revoked`; unknown custom types still return `RpcUnknown`.
- Added `cockpit/test/data/rpc_event_mapper_test.dart` covering existing relay/name payload fields unchanged, the new schema-neighbor events, and unknown custom-event degradation.
- Verification: `flutter pub get --offline` passed; `flutter analyze` passed with 0 issues; `flutter test` passed (226/226).
- Discrepancies: generated Dart output does not yet include `cockpitControl` DTOs, so this step aligns Cockpit to the checked-in schema vocabulary by hand-domain values while preserving legacy transport serialization for later structured-emission steps.


## Review

Approved (2026-06-30). Independently re-ran: whole-cockpit `flutter analyze` →
No issues found; full `flutter test` → 226/226 (incl. new rpc_event_mapper_test).
Commit `7aae1f2` scoped to cockpit only (rpc_event_mapper + pi_rpc_process +
rpc_process_gateway + pi_command + rpc_event + the UI consumers that call
sendControl + story .md); no cross-subproject collision.

Typed abstraction verified: `sendControl` takes `PiControlCommand` (not raw
verb String); typed event set covers all 5 overlay events
(remote-pi:relay-state, name-assigned, pair-code, paired, mesh-revoked);
RpcUnknown degradation preserved for unknown custom types. No runtime behavior
change — `PiRpcProcess` still serializes to the existing NUL-prefixed `prompt`
compatibility frame (centralized in the gateway adapter); existing relay/name
payload fields unchanged. The deviation (generated Dart lacks cockpitControl
DTOs yet, so hand-domain values align to the schema vocabulary while preserving
legacy transport) is a legitimate first-boundary-step approach, documented.
