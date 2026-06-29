---
id: epic-bold-generated-protocol-ts-codegen
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension]
parent: epic-bold-generated-protocol
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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

<!-- /agile-workflow:refactor-design fills in the codegen + migration approach. -->
