---
name: scan-protocol-contract
description: >
  Remote-Pi single-source-of-truth protocol scan. Enforces that wire message types, room/session
  metadata fields, and frame discriminators are defined once (generated or a canonical registry)
  and derived everywhere else — not re-enumerated in separate validators, UI labels, handlers,
  and tests. Grounded in `.agents/rules/code-design.md` (Single source of truth + Generated or
  inferred contracts). Auto-loads as a gate-refactor rule library via glob `scan-*/SKILL.md`.
allowed-tools: Read, Glob, Grep
---

# Protocol Contract Scan

Scans the release bundle's changed files for single-source-of-truth violations on the wire
protocol: handwritten message-type strings or frame discriminators that duplicate a generated
registry, and handwritten wire DTOs that duplicate a generated shape. Each rule has a reference
file with rationale, real file:line examples, and exceptions. Loaded by `gate-refactor` when
`gates_for_release` includes `refactor`.

findings-route: none

## Why this library is UNTAGGED

The fixes are mixed and the route is per-library, so the honest call is untagged. *Some* fixes
are behavior-preserving (replacing a literal `"room_meta_update"` with a constant that holds the
same string, when the constant is the generated source of truth). But others are
behavior-changing: migrating a documented temporary hand-maintained island
(`app/lib/protocol/control_frames.dart`) into the generated schema changes the wire shape's
provenance and may change validation/error behavior; replacing a handwritten DTO with a generated
one can alter field presence or defaulting. Since the tagged route requires the black-box test to
hold for *every* rule's fix and that is not defensible for the island-migration rules, the whole
library is untagged and findings route through story/feature design. This matches SNC platform's
posture (all 8 scan libraries untagged).

## Rules

| Rule | Slug | What to check | Reference |
|------|------|---------------|-----------|
| Handwritten type string duplicates registry | `handwritten-type-string` | A wire message-type/frame-type literal string that duplicates a value in a generated `as const` registry or generated enum | [details](references/handwritten-type-string.md) |
| Handwritten wire DTO duplicates generated | `handwritten-wire-dto` | A struct/class defining a wire frame shape that duplicates a generated DTO, instead of importing/re-exporting it | [details](references/handwritten-wire-dto.md) |
| Frame discriminator re-enumerated | `discriminator-reenumerated` | A `switch`/`match`/validator that re-lists frame type strings instead of deriving from the canonical registry | [details](references/discriminator-reenumerated.md) |
| Undocumented protocol island | `undocumented-protocol-island` | Hand-maintained wire types outside `generated/` without a documented reason they are not yet in the schema | [details](references/undocumented-protocol-island.md) |

## Confidence Mapping

| Finding type | Typical confidence | Lane |
|---|---|---|
| Literal type string that exactly matches a generated registry value | high | Fix — replace with the constant |
| Handwritten DTO with fields duplicating a generated struct | high | Fix — import/re-export instead |
| `switch(match s) { "peer_online" => ... }` re-listing registry strings | medium | Analyze — may need a derived exhaustive union |
| Hand-maintained island WITH a documented reason (e.g. `control_frames.dart`) | low | Skip — documented exception |
| Hand-maintained island WITHOUT a documented reason | medium | Analyze — migrate to schema (behavior-changing) |
| Generated re-export facade (`pub use generated::*`) | low | Skip — correct pattern |

## Output Format

Findings are produced by the gate-refactor scanner agent as structured items (see
`gate-refactor/SKILL.md` Phase 3 brief). Each finding cites `file:line`, the violated slug, and a
specific proposed change (or "needs analysis" for medium). Do not emit findings for the
explicitly exempted sites in each reference file's **Exceptions** section — generated re-export
facades and documented islands are legitimate.

## Cross-rule delineation (avoid double-counting)

A single hand-maintained protocol island (e.g. `app/lib/protocol/control_frames.dart`) can look
like several rules at once: a `switch` re-listing literals (`discriminator-reenumerated`), the
literals themselves (`handwritten-type-string`), and an island (`undocumented-protocol-island`).
Report it under exactly one rule, by priority:

1. **If the island is UNdocumented** → `undocumented-protocol-island` (the missing provenance is
   the root cause; the re-enumeration and literals are symptoms that migration will resolve).
2. **If the island IS documented** → it is an exception: do NOT flag `discriminator-reenumerated` or
   `handwritten-type-string` against a documented island's literals/switch (they will be resolved
   by the eventual schema migration, which is its own behavior-changing story). Emit nothing for a
   documented island unless a NEW undocumented type appears inside it.
3. **If a literal duplicates a generated registry value in a non-island file** (the same
   subproject's generated registry actually contains it) → `handwritten-type-string`.
4. **If a `switch` re-lists registry values in a non-island file** → `discriminator-reenumerated`.

Do not emit two findings for the same `file:line` under two of these rules; pick by the priority
above. The documented-island exception (`control_frames.dart`) suppresses `handwritten-type-string`
and `discriminator-reenumerated` for the Dart literals because the Dart generated registry does
not contain relay control frames — see `handwritten-type-string`'s language-conditional note.

## Scope

- Applies to: `relay/src/protocol/**` and `relay/src/handlers/**` (non-test), `relay/src/peers/**`
  (non-test), `pi-extension/src/protocol/**` and `pi-extension/src/transport/**` (non-test),
  `app/lib/protocol/**` (non-test, non-generated), `cockpit/lib/**` protocol touch sites
- Does NOT apply to: generated code (`protocol/generated/`, `*.g.dart`), test files
  (`*.test.ts`, `_test.dart`, `relay/tests/**`, `#[cfg(test)]`), `site/**`
