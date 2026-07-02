---
id: gate-docs-protocol-source-stale-handwritten-claims
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# Protocol docs still describe handwritten protocol mirrors as current truth

## Severity
High

## Location
- `docs/ARCHITECTURE.md:52-56, 63-67, 139-143`
- `docs/SPEC.md:46-82`
- `docs/DECISIONS.md:90-100`

## Issue
The docs still describe core protocol definitions as a handwritten/legacy mirror split across multiple surfaces and call a handwritten approach the de-facto source of truth.

## Evidence (current runtime)
- `pi-extension/src/protocol/types.ts` is now a narrow re-export of generated protocol types from `./generated/protocol.generated.ts`.
- `pi-extension/src/protocol/codec.ts` dispatches decode/encode over generated helpers (`decodeServer`, `decodeClient`, generated type sets) and `DecodeError` variants, instead of maintaining a handwritten master schema.
- `app/lib/protocol/protocol.dart` imports/exports `generated/protocol.g.dart` and only adds a documented temporary hand-maintained island (`control_frames.dart`).
- `relay/src/protocol/outer.rs` depends on `generated/outer.rs` for the outer envelope and its parse/encode pathway.
- `relay/src/protocol/generated/outer.rs` is generated code with a schema-originating contract path.

## Required update
`docs/ARCHITECTURE.md`, `docs/SPEC.md`, and `docs/DECISIONS.md` should be revised to treat generated protocol artifacts as the current source-of-truth for message/type enums and frame parsing, and explicitly call out only the temporary documented hand-maintained protocol islands.
