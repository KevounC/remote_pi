---
id: epic-bold-generated-protocol-cockpit-control-rpc
kind: feature
stage: implementing
tags: [refactor, bold, cockpit, pi-extension]
parent: epic-bold-generated-protocol
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Generated protocol — fold cockpit control transport into schema/types

## Brief

Retire the `\x00remote-pi-ctrl:` NUL-prefix control protocol between Cockpit and the
pi-extension by routing it through the generated protocol family (`cockpit-control`)
for both transport peers:

- Cockpit `pi --mode rpc` prompt control channel.
- pi-extension `input` hook (`CTRL_PREFIX`) in the same transport path today.

Today both sides ship ad-hoc string contracts (`CTRL_PREFIX`, `relay:on`, `relay:toggle`,
`rename:...`) and manually mapped custom events (`remote-pi:relay-state`,
`remote-pi:name-assigned`, plus undocumented `remote-pi:pair-code`,
`remote-pi:paired`, `remote-pi:mesh-revoked`).

This feature moves the contract to schema-owned definitions (`protocol/schema/cockpit-control.schema.json`) while keeping explicit legacy compatibility during rollout so the long-lived fork can co-exist with mixed client versions.

## Epic context

- Parent epic: `epic-bold-generated-protocol`
- Position: transport-boundary refactor for the cockpit control overlay.
- Sibling scope: `epic-bold-generated-protocol-schema-source` (done/implementing) defines the canonical schema namespace; 
  `epic-bold-generated-protocol-dart-codegen` and `epic-bold-generated-protocol-ts-codegen`
  consume that schema.
- Cross-surface constraint: this work must stay patchbay-friendly and not entrench bespoke transport glue that blocks later migration.

## Current

Cockpit and extension still rely on duplicate string conventions:

```ts
// pi-extension/src/index.ts
export const CTRL_PREFIX = "\x00remote-pi-ctrl:";
export async function _handleControl(cmd: string): Promise<void> { ... relay:on/off/toggle/status + rename:... }
if (event.text.startsWith(CTRL_PREFIX)) {
  void _handleControl(event.text.slice(CTRL_PREFIX.length).trim());
  return { action: "handled" };
}
```

```dart
// cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart
static const _ctrlPrefix = '\x00remote-pi-ctrl:';
await _writeLine(jsonEncode({'type': 'prompt', 'message': '$_ctrlPrefix$verb'}) + '\n');
```

```dart
// cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart
switch (customType) {
  case 'remote-pi:relay-state': ...
  case 'remote-pi:name-assigned': ...
  default: RpcUnknown
}
```

The interface docs/comments still describe string verbs, and the contract does not
yet include the generated schema vocabulary for both sides of the control path.

## Target

- Use the schema family from `protocol/schema/cockpit-control.schema.json` as the
  single source for:
  - relay control command vocabulary
  - pair/relay status custom event payload shapes
  - compatibility encoding metadata (`x-remote-pi.compatEncoding: "nul-prefixed-prompt"`)
- Keep `input` parsing logic tolerant in extension (`CTRL_PREFIX` legacy + structured
  control message), with a single dispatch target to avoid control/mesh duplication.
- Preserve runtime behavior during rollout:
  - `relay:on|off|toggle|status` and rename flows remain functional with no
    transcript noise.
  - custom events remain `{customType, details, ...}` for existing UI consumers.

## Notes (rationale)

- **Why schema-first while keeping compatibility?**
  The fork already supports mixed runtime versions across users/devices; hard-cut
  removal of `CTRL_PREFIX` would create a one-way migration risk. The schema already
  documents legacy encoding, so we should preserve that path as compatibility and move
  the canonical path to structured commands.

- **Why map additional custom events now?**
  `remote-pi:pair-code`, `remote-pi:paired`, and `remote-pi:mesh-revoked` are part
  of the same overlay transport and should be represented in the same canonical event
  registry used by schema/codegen, even if cockpit UI handling evolves in future
  steps. This avoids drift between transport overlays.

- **Patchbay compatibility guardrail:**
  Do not introduce domain code that assumes Pi `pi` internals or current
  extension implementation details; keep this as protocol-to-adapter mapping with a
  small transport envelope.

## Refactor Steps (chained stories)

1. `epic-bold-generated-protocol-cockpit-control-rpc-step-1`
   - Add Cockpit-side schema-aligned control domain + event mapping:
     - `RpcEvent`/`RpcEventMapper` typed events for control overlay.
     - `RpcProcessGateway.sendControl` shifts from raw verb `String` to schema command
       object/enum input.
     - `pi_rpc_process.dart` serializes schema control commands (with temporary
       fallback to legacy strings where needed by transport path).

2. `epic-bold-generated-protocol-cockpit-control-rpc-step-2`
   - Update pi-extension control input parsing and router:
     - parse schema control payloads first.
     - preserve `CTRL_PREFIX` handling as a compatibility decoder.
     - keep behavior-orthogonal `relay`/`rename` branching and existing `_emitRelayState`
       event emission semantics.
     - expand tests around both legacy and structured control frames.

3. `epic-bold-generated-protocol-cockpit-control-rpc-step-3`
   - Close the transport mapping loop:
     - include full custom event map (`relay-state`, `name-assigned`, `pair-code`,
       `paired`, `mesh-revoked`) in Cockpit adapter/domain.
     - ensure protocol docs/tests treat these as schema-aligned fixtures.
     - record generated-schema migration rationale in this feature body.

## Implementation Order

- Step 1 → Step 2 → Step 3, each depends on the previous.
- Step 1 explicitly depends on `epic-bold-generated-protocol-schema-source`.

## Acceptance

- [ ] The cockpit control path and custom control overlay events are represented by
  generated schema artifacts and mapped by typed adapters.
- [ ] `pi-extension/src/index.ts` accepts both legacy NUL-prefixed payloads and
  schema-shaped control objects; legacy path remains explicit by design.
- [ ] `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart` no longer relies on
  inline magic strings as the only wire for control verbs.
- [ ] `remote-pi:relay-state`, `remote-pi:name-assigned`, `remote-pi:pair-code`,
  `remote-pi:paired`, `remote-pi:mesh-revoked` are handled through the same schema
  event family.
- [ ] No production wire behavior is changed outside the intended control overlay
  (`type/message` framing and event payload shape compatibility preserved).

## Risk

- **Behavior regression**: wrong parsing fallback order could swallow non-control RPC
  input. Mitigation: explicit discriminator + unit tests for legacy + structured
  frames.
- **Event surface growth risk**: expanding mapped custom events can expose unhandled
  cases. Mitigation: keep unknowns as `RpcUnknown` and surface only known cases to
  typed entities.
- **Migration risk**: if both sides are switched inconsistently, relay control UI
  could fail to sync on reconnect. Mitigation: keep NUL-prefixed compatibility
  decode until generated schema consumer adoption is complete.

## Rollback

- Revert feature stories once implemented:
  - back to `CTRL_PREFIX`-only Cockpit sender/handler behavior;
  - restore old `_ctrlPrefix`/`_handleControl(String)`/string switch wiring;
  - restore old `RpcEventMapper` string matching without new typed control schema
    classes.
- This rollback is behavior-safe and does not touch relay/app meshes or core
  process lifecycle semantics.

