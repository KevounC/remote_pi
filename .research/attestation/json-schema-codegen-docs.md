---
source_handle: json-schema-codegen-docs
fetched: 2026-06-28
source_url: https://github.com/ajv-validator/ajv/blob/HEAD/docs/codegen.md
provenance: source-direct
---

# JSON Schema / codegen attestation

1. AJV docs/search metadata describe AJV as a TypeScript JSON Schema validator supporting JSON Schema draft-04/06/07/2019-09/2020-12 and JSON Type Definition (RFC8927).
2. Search results for Rust-to-TypeScript generation mention `schemars` deriving JSON Schema from Rust types and `json-schema-to-typescript` generating TypeScript definitions from schemas.
3. A Turborepo schema-gen README search result describes generating JSON Schema and TypeScript type definitions from Rust types, using `schemars` and `ts-rs`, with a verify command to check generated files are up to date.
4. JSON Schema/codegen results showed many possible tools, but no single source in this pass established a mature Rust+TypeScript+Dart roundtrip equivalent to Protobuf/Buf's multi-language schema workflow.
