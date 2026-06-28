---
source_handle: protobuf-buf-docs
fetched: 2026-06-28
source_url: https://buf.build/docs/breaking/ and https://protobuf.dev/reference/dart/dart-generated/
provenance: source-direct
---

# Protobuf / Buf attestation

1. Buf docs state `buf breaking` compares the current Protobuf schema against a past version and reports changes that would break clients, servers, or generated code.
2. Buf usage docs state breaking checks take current schema and a baseline via `--against` or `--against-registry`.
3. Buf docs describe `buf lint` as reading configuration from `buf.yaml` and running lint/breaking rules.
4. Buf GitHub/docs describe Buf as a modern Protobuf toolchain replacing day-to-day `protoc` use with compile, formatting, linting, breaking-change detection, code generation, dependency management, API calls, and registry support.
5. Protobuf docs include Dart generated-code documentation, showing official Dart code generation exists for `.proto` definitions.
6. Rust search results identify `prost` as a Rust Protocol Buffers implementation that generates Rust code from `.proto` files, and `tonic`/`tonic-build` as Rust gRPC/service stub code generation.
7. TypeScript search results identify `ts-proto` and `protobuf-ts` as TypeScript Protobuf code generators.
