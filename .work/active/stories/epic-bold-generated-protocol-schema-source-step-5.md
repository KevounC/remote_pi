---
id: epic-bold-generated-protocol-schema-source-step-5
kind: story
stage: review
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-generated-protocol-schema-source
depends_on: [epic-bold-generated-protocol-schema-source-step-4]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 5: Add schema validation checks and generator handoff contracts

**Priority**: High  
**Risk**: Low  
**Source Lens**: generated contracts / fail fast  
**Files**: `protocol/package.json`, `protocol/scripts/check-fixtures.ts`, `protocol/scripts/list-types.ts`, `protocol/fixtures/**`, `protocol/README.md`, `.orchestration/contracts/protocol.md` (read-only reference or deprecation note only if needed)

## Current State

The current cross-language contract is prose plus fixtures under `.orchestration/contracts/`, but it is not derived from the actual source and omits newer current messages:

```md
# .orchestration/contracts/protocol.md
Fixtures folder carries 1 JSONL example per `type`. Each subproject runs its codec against these files.
Changes here are breaking — align the 3 codecs before committing.
```

The actual message set has outgrown those fixtures (`queued_message_state`, typed actions, `models_list`, `compaction`, image-bearing `user_message`, room `thinking`/`working`, cockpit custom events), and there is no single registry that a generator can consume.

## Target State

Add a local schema validation harness and a generator handoff manifest so later TS/Dart/Rust codegen stories consume the same registry rather than re-discovering message names.

```json
{
  "name": "@remote-pi/protocol-schema",
  "private": true,
  "type": "module",
  "scripts": {
    "check": "tsx scripts/check-fixtures.ts",
    "list-types": "tsx scripts/list-types.ts"
  },
  "devDependencies": {
    "ajv": "^8.17.0",
    "ajv-formats": "^3.0.0",
    "tsx": "^4.22.0",
    "typescript": "^6.0.3"
  }
}
```

```ts
// protocol/scripts/check-fixtures.ts
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";
import { readFileSync } from "node:fs";

const ajv = new Ajv2020({ strict: true, allErrors: true, allowUnionTypes: false });
addFormats(ajv);
// Load schema files from protocol/schema, compile each family, then validate
// every JSONL object in protocol/fixtures/<family>/*.jsonl.
```

```ts
// protocol/scripts/list-types.ts
// Reads protocol/schema/manifest.json and emits the canonical type catalog:
// family, transport, type, schema ref, compat/canonical-session requirements.
// TS/Dart/Rust codegen stories use this output as their contract input.
```

## Implementation Notes

- Keep the validation harness in `protocol/` so it does not make `pi-extension`, `app`, `relay`, or `cockpit` own the schema package.
- Existing `.orchestration/contracts/fixtures/*.jsonl` can be copied into `protocol/fixtures/` during this step. Do not delete `.orchestration/contracts/` until generated consumers and docs explicitly retire it.
- `check-fixtures.ts` should fail when a fixture type is unknown, when a fixture violates its schema, or when a manifest type lacks fixture coverage unless explicitly listed under `x-remote-pi.fixtureOptional`.
- `list-types.ts` is intentionally simple: it is the stable handoff from schema-source to sibling codegen features, not a language generator.

## Acceptance Criteria

- [ ] `corepack pnpm --dir protocol check` validates every protocol fixture against the schema.
- [ ] `corepack pnpm --dir protocol list-types` emits a deterministic catalog of all manifest message types and their families.
- [ ] The check fails for the exact drift class seen in `codec.ts` (a live type in the schema missing from a generated/server registry).
- [ ] `protocol/README.md` explains how future TS/Dart/Rust generator stories consume the manifest and fixture catalog.
- [ ] `.orchestration/contracts/` remains available as legacy reference until the generated protocol consumers replace it.

## Rollback

Remove the validation scripts, protocol package metadata, and newly copied fixtures. The schema files from earlier steps may remain usable as static documents, and no runtime consumer rollback is required.

## Implementation notes

- Added protocol package scripts and dev dependencies for AJV 2020-12 fixture validation and generator type-catalog emission.
- Added `protocol/scripts/check-fixtures.ts`, which loads all schema files with `$id`, compiles each manifest family, and validates configured JSONL fixtures for app-pi client/server, relay control/outer, cross-PC, and cockpit control.
- Added `protocol/scripts/list-types.ts`, which emits deterministic JSON catalog entries with family, transport, discriminator, type/customType/untagged id, schema ref, and profile-required fields for downstream TS/Dart/Rust generator stories.
- Updated `protocol/README.md` with package commands, fixture/catalog semantics, and the rule that `.orchestration/contracts/` remains a legacy reference until generated consumers replace it.
- Script entrypoints use `node --import tsx ...` rather than the bare `tsx` CLI because this harness rejects tsx's IPC pipe listen with `EPERM`; the package still depends on `tsx` for TS execution.
- Verification run from repo root: `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store check` passed; `corepack pnpm --dir protocol --config.store-dir=/tmp/remote-pi-pnpm-store list-types` emitted 58 catalog entries and valid JSON. Install was run with `NPM_CONFIG_USERCONFIG=/tmp/remote-pi-empty-npmrc` and a local temp store because the default home npmrc/store were not writable in this harness.
