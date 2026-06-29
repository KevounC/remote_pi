---
id: epic-bold-generated-protocol-ts-codegen-step-1
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# TS codegen step 1 — generator target and schema handoff

## Brief
Add the TypeScript target to the shared protocol-codegen tooling. It consumes `protocol/schema/manifest.json` plus JSON Schema 2020-12 family schemas, builds the normalized Remote Pi IR, and emits deterministic TS spike output beside the current handwritten protocol files without switching runtime imports.

## Current State

```ts
// pi-extension/src/protocol/types.ts is authored by hand and acts as the
// de-facto source for TypeScript instead of consuming protocol/schema/.
export type ClientMessage =
  | { type: "pair_request"; id: string; token: string; device_name: string }
  | { type: "user_message"; id: string; text: string; images?: WireImage[]; streaming_behavior?: StreamingBehavior }
  | { type: "list_models"; id: string };
```

## Target State

```ts
// tools/protocol-codegen/src/index.ts
const manifest = await loadRemotePiManifest("protocol/schema/manifest.json");
const ir = await buildRemotePiIr(manifest, { profile: "compat" });
await emitTypeScriptProtocol(ir, {
  outFile: "pi-extension/src/protocol/generated/protocol.generated.ts",
});
```

## Implementation Notes

- Put shared generator logic under `tools/protocol-codegen/` so TS and Dart use the same normalized IR instead of separate schema walkers.
- The TS target waits for schema-source family schemas to be filled; if only placeholders exist, fail with a clear "schema family placeholder" diagnostic.
- Emit deterministic output order from `manifest.json`, not filesystem traversal.
- Do not switch `pi-extension/src/protocol/types.ts` or runtime imports in this step.
- Keep TypeScript ESM/NodeNext constraints in mind for any generated split-file imports.

## Acceptance Criteria

- [ ] A TS generator target can load the protocol manifest and build a normalized IR.
- [ ] Placeholder/incomplete schema families fail with a clear diagnostic.
- [ ] A minimal fixture schema emits deterministic TS output in a generator test.
- [ ] Existing pi-extension runtime behavior is unchanged.

## Risk
Medium — generator architecture choices affect TS/Dart/Rust parity, but no runtime code switches in this step.

## Rollback
Delete the TS generator target and generated spike output; no runtime code depends on it.
