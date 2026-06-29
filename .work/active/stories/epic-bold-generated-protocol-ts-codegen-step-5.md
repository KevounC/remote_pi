---
id: epic-bold-generated-protocol-ts-codegen-step-5
kind: story
stage: implementing
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-ts-codegen-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# TS codegen step 5 — generated-protocol parity checks and package scripts

## Brief
Add stale-generation and schema parity checks to the pi-extension workflow so generated TS output cannot drift from `protocol/schema/` and no new handwritten protocol variant registry appears in tests.

## Current State

```json
{
  "scripts": {
    "build": "tsc",
    "typecheck": "tsc --noEmit",
    "test": "vitest run"
  }
}
```

The current codec test has a handwritten server fixture allowlist, which repeats the same drift pattern as `codec.ts`.

## Target State

```json
{
  "scripts": {
    "generate:protocol": "tsx ../tools/protocol-codegen/src/index.ts --target ts --out src/protocol/generated/protocol.generated.ts",
    "check:protocol": "pnpm generate:protocol --check",
    "typecheck": "tsc --noEmit",
    "test": "vitest run"
  }
}
```

```ts
// Generated parity test shape.
expect(SERVER_MESSAGE_TYPES).toContain("models_list");
expect(new Set(SERVER_MESSAGE_TYPES)).toEqual(schemaServerTypeSet);
```

## Implementation Notes

- Add a check mode that fails when generated TS output is stale relative to `protocol/schema/manifest.json` and family schemas.
- Keep generated source committed because `pi-extension/` publishes from `src -> dist` and consumers should not need the generator at runtime.
- Keep `.orchestration/contracts/` only as legacy fixtures until the full generated-protocol epic replaces it.
- Derive fixture classification and type coverage from the schema/IR or generated registries, not from a handwritten test allowlist.
- Record any schema incompleteness as an implementation note in this feature body rather than weakening tests.

## Acceptance Criteria

- [ ] `corepack pnpm --dir pi-extension check:protocol` fails on stale generated output.
- [ ] Type registry parity is derived from schema/IR, not a handwritten test allowlist.
- [ ] `corepack pnpm --dir pi-extension typecheck`, `test`, and `build` pass.
- [ ] No generated `dist/` or local build artifacts are committed.

## Risk
Medium — package scripts and generated-output checks can be brittle if paths differ between root and subproject runs; test both invocation forms documented in the story.

## Rollback
Remove the package scripts and parity tests; generated runtime code from earlier steps remains controlled by normal typecheck/test until restored.
