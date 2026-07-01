---
id: epic-bold-generated-protocol-ts-codegen-step-5
kind: story
stage: review
tags: [refactor]
parent: epic-bold-generated-protocol-ts-codegen
depends_on: [epic-bold-generated-protocol-ts-codegen-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
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

## Implementation

- Files changed: `pi-extension/package.json`, `pi-extension/src/protocol/codec.test.ts`, `tools/protocol-codegen/src/index.ts`.
- Parity checks: `codec.test.ts` now derives app/Pi client and server type sets from `protocol/schema/manifest.json` through the shared TS codegen IR and compares those sets to `CLIENT_MESSAGE_TYPES` / `SERVER_MESSAGE_TYPES`; it explicitly guards `models_list` and `list_models` without a handwritten variant allowlist.
- Package scripts: from repo root, run `corepack pnpm --dir pi-extension generate:protocol` or `corepack pnpm --dir pi-extension check:protocol`; from `pi-extension/`, run `corepack pnpm generate:protocol` or `corepack pnpm check:protocol`. The script uses `node --import tsx` rather than bare `tsx` because this sandbox's `tsx` CLI IPC path fails with `listen EPERM` on `/tmp/tsx-*/*.pipe`.
- Check mode: `corepack pnpm --dir pi-extension check:protocol` was verified to fail after a temporary stale marker was appended to `src/protocol/generated/protocol.generated.ts` (`Generated TypeScript protocol is stale: src/protocol/generated/protocol.generated.ts`), then the committed file was restored and the check passed.
- Generated-contract regen result: generator output is deterministic; two fresh temp generations diffed empty against each other and against `pi-extension/src/protocol/generated/protocol.generated.ts`. No generated source changed.
- Verification:
  - `corepack pnpm --dir pi-extension check:protocol` — passed.
  - `cd pi-extension && corepack pnpm check:protocol` — passed.
  - `corepack pnpm typecheck` — passed.
  - `corepack pnpm build` — passed.
  - `node --import tsx --test ../tools/protocol-codegen/src/index.test.ts` — 5 passed, 0 failed.
  - `corepack pnpm exec vitest run --reporter=dot src/protocol/codec.test.ts` — 86 passed, 0 failed.
  - Full `corepack pnpm exec vitest run --reporter=dot` was re-run twice and hit the known environment false-failure pattern, not protocol/codec/listener-count regressions: both clean runs reported 649 passed, 3 skipped, 66 failed across `src/daemon/supervisor.test.ts`, `src/session/cwd_lock.test.ts`, `src/session/e2e.test.ts`, and `src/session/leader_election.test.ts` with `listen EPERM`, cwd-lock acquire assertions, and `leader election failed` signatures. No parity, codec, message type, listenerCount, or delivery-count tests failed.
- Discrepancies from design: `check:protocol` uses `corepack pnpm generate:protocol --check` (not bare `pnpm ...`) so it works in this harness where `pnpm` is not on PATH inside lifecycle scripts; `generate:protocol` uses `node --import tsx` for the same environment reason noted above.
- Adjacent issues parked: none.

## Rollback
Remove the package scripts and parity tests; generated runtime code from earlier steps remains controlled by normal typecheck/test until restored.
