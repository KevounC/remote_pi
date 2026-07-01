---
id: epic-bold-generated-protocol-ts-codegen-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-schema-source]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

- [x] A TS generator target can load the protocol manifest and build a normalized IR.
- [x] Placeholder/incomplete schema families fail with a clear diagnostic.
- [x] A minimal fixture schema emits deterministic TS output in a generator test.
- [x] Existing pi-extension runtime behavior is unchanged.

## Risk
Medium — generator architecture choices affect TS/Dart/Rust parity, but no runtime code switches in this step.

## Rollback
Delete the TS generator target and generated spike output; no runtime code depends on it.

## Implementation

Implemented the TypeScript codegen spike in `tools/protocol-codegen/src/index.ts` and wired `--target ts` through `tools/protocol-codegen/bin/protocol-codegen.mjs`. The TS target loads `protocol/schema/manifest.json`, walks manifest families in manifest order, resolves JSON Schema 2020-12 `$ref` references, builds a normalized `RemotePiIr`, and emits `pi-extension/src/protocol/generated/protocol.generated.ts` beside the handwritten protocol files. Runtime imports remain unchanged.

The emitted spike output includes deterministic family/type registries and schema-derived TypeScript interfaces/unions. Placeholder or incomplete schema families fail fast with a clear `schema family placeholder: <family> (<schema>) ...` diagnostic. A minimal fixture schema test asserts exact deterministic output, and stale generated-output check mode is covered.

Verification:

- Generator tests: `node --test tools/protocol-codegen/src/index.test.ts` — 3 passed / 0 failed.
- Regen check: `cd protocol && node --import tsx scripts/list-types.ts | node ../tools/protocol-codegen/bin/protocol-codegen.mjs --target ts --schema - --out-dir ../pi-extension/src/protocol/generated --check` — passed.
- Determinism double-run: generated twice to temp dirs and `diff -r` was empty.
- Regen diff vs generated file: generated to a temp dir and `diff -u` against `pi-extension/src/protocol/generated/protocol.generated.ts` was empty.
- Pi-extension typecheck: `corepack pnpm typecheck` with repo-local pnpm caches — passed.
- Pi-extension vitest: root `corepack pnpm exec vitest run --dir pi-extension 2>/dev/null || true` cannot run because repo root has no `package.json`; running from `pi-extension/` executed 673 tests with 604 passed / 66 failed / 3 skipped due existing sandbox UDS/cwd-lock environment failures (`listen EPERM` and leader-election/cwd-lock failures), unrelated to generated TS.

## Review

Approved (2026-06-30) with GENERATED-CONTRACT verification. Independently verified
all three generated-contract invariants:
1. **Determinism double-run**: two temp dirs, `diff -r` EMPTY ✓
2. **No hand-edits**: regen-diff vs committed `protocol.generated.ts` EMPTY ✓
3. **pi-ext typecheck + suite**: clean; **670 passed | 3 skipped | 0 failed (44 files)** ✓

Commit `913a66b` scoped to tools/ + pi-ext only (generator `index.ts` +548 +
`index.test.ts` +153 + `bin` wiring + generated `protocol.generated.ts` 666 lines +
story .md); collision guard held. Runtime imports unchanged (handwritten
`types.ts` remains de-facto source; generated spike sits beside it).

### Test-invocation environment note
The orchestrator's `node --test --import tsx tools/protocol-codegen/src/index.test.ts`
fails with `ERR_MODULE_NOT_FOUND: Cannot find package 'tsx'` — because `tsx` is a
pi-extension dependency, not resolvable from the repo root in the orchestrator's
invocation context. This is an ENVIRONMENT issue (missing prerequisite on the
resolution path), NOT a real test failure — classified per `.agents/rules/testing-
integrity.md` "Environment issue". The test file's imports are sound; running it from
within the pi-extension dependency context (as the agent did) passes 3/0. The
generated-contract invariants above are the load-bearing verification for this
story, and all pass.
