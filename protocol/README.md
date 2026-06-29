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
- Family schemas are created as side-by-side placeholders in Step 1 and are filled by later schema-source stories.

Profiles:

- `compat` describes the current compatibility wire.
- `canonical-session` records the future `session_id`/`turn_id` enforcement target without changing live behavior in this step.
