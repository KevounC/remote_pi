# Remote Pi protocol schema

`protocol/schema/` is the canonical schema source for generated protocol work. It is intentionally a repo-root package because the wire spans the Pi extension, mobile app, relay, cockpit control overlay, and future code generators.

The committed source is **JSON Schema 2020-12** plus Remote Pi generator metadata under `x-remote-pi`. Runtime consumers are not switched by the schema-source Step 1 story; current TS/Dart/Rust mirrors remain live until their generator/adoption stories land.

## Why JSON Schema first

JSON Schema matches the existing discriminated JSONL wire and can feed TypeScript, Dart, and Rust generators without making one runtime language the source of truth. Generator-only facts such as family ids, transport, profiles, and compatibility encodings live under `x-remote-pi` so the standards-based schema remains portable.

Rejected alternatives for this fork-private bold refactor:

- **Protobuf/Buf**: attractive for a future rigorous/patchbay rewrite, but default Protobuf JSON mapping fights the existing `{ "type": ... }` shape and would require a custom JSON bridge before the current wire is under control.
- **TypeScript-native schemas** (`zod`, TypeBox, Valibot): pleasant for TS but would keep Dart and Rust downstream of a TS derivative, recreating the source/derivative ambiguity this refactor removes.
- **Custom IDL**: could fit Remote Pi closely, but would create a new protocol language to maintain and would travel worse to patchbay than a neutral schema.

## Layout

- `schema/remote-pi.schema.json` — umbrella schema and shared metadata.
- `schema/manifest.json` — deterministic family registry for generators.
- `schema/defs/common.schema.json` — shared scalar/JSON definitions.
- `schema/defs/agent-envelope.schema.json` — generic `{from,to,id,re,body}` agent envelope used by local/cross-PC mesh.
- Family schemas define app↔Pi, relay control/outer, cross-PC, cockpit control, and reachability contract surfaces.
- `fixtures/<family>/*.jsonl` — compatibility examples validated by the schema check.
- `scripts/check-fixtures.ts` — compiles schemas and validates every configured fixture.
- `scripts/list-types.ts` — emits the deterministic generator handoff catalog.

Profiles:

- `compat` describes the current compatibility wire.
- `canonical-session` records the future `session_id`/`turn_id` enforcement target without changing live behavior in this step.

## Commands

Run from the repo root or this package:

```bash
corepack pnpm --dir protocol install
corepack pnpm --dir protocol check
corepack pnpm --dir protocol list-types
```

`check` fails when a fixture violates its family schema or when a configured fixture file is empty/missing. `list-types` prints JSON entries with `family`, `transport`, discriminator (`type`, `customType`, or `untagged`), schema ref, and profile-required fields. The TS, Dart, and Rust generator stories consume this catalog instead of re-discovering message names independently.

`.orchestration/contracts/` remains a legacy cross-language reference until generated consumers replace it; do not delete it as part of schema-source work.
