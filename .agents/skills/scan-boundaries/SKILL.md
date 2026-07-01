---
name: scan-boundaries
description: >
  Remote-Pi ports-and-adapters boundary scan. Enforces that domain/core logic does not
  import infrastructure directly and that untrusted wire/config data is not parsed into
  ad-hoc maps deep in business logic. Grounded in `.agents/rules/code-design.md`
  (Ports and Adapters + Fail fast at boundaries). Auto-loads as a gate-refactor rule
  library via glob `scan-*/SKILL.md`.
allowed-tools: Read, Glob, Grep
---

# Boundary Scan

Scans the release bundle's changed files for ports-and-adapters violations. Each rule has a
reference file with rationale, real file:line examples from this repo, and exceptions. Loaded
by `gate-refactor` when `gates_for_release` includes `refactor`.

findings-route: none

## Why this library is UNTAGGED

The fixes these rules propose are **not** guaranteed behavior-preserving. Converting a value
import to type-only can change when an imported module's top-level side effects run; replacing
ad-hoc `serde_json::Value` navigation with a typed deserialize can change which error branch
fires, when missing fields are rejected, and what malformed input is accepted; parsing an
ambiguous blob into a DTO at the boundary is fail-fast *behavior* (errors surface earlier and
differently). Each of these changes observable behavior for some caller. Per the gate-refactor
contract, the tagged-refactor route requires the black-box test to hold for *every* rule's
fix — that is not defensible here, so the library is untagged and findings route through normal
story/feature design (where the behavior change is designed explicitly, not smuggled through as
a refactor). This matches SNC platform's posture: all 8 of its scan libraries are untagged.

## Rules

| Rule | Slug | What to check | Reference |
|------|------|---------------|-----------|
| Domain imports infra | `domain-imports-infra` | Domain/core modules importing transport, storage, platform, or SDK infrastructure directly | [details](references/domain-imports-infra.md) |
| Value import of infra in core | `infra-value-import-in-core` | Core logic taking a concrete infra *value* (not a type-only import) — couples construction/side-effects | [details](references/infra-value-import-in-core.md) |
| Ad-hoc wire parse in handler | `ad-hoc-wire-parse` | Business/handler code parsing wire payloads into `serde_json::Value` / ad-hoc maps and navigating with `.get()` instead of a typed DTO | [details](references/ad-hoc-wire-parse.md) |
| Ambiguous map passed to domain | `ambiguous-map-to-domain` | Passing untyped `Record`/`Map`/`HashMap`/`Value` blobs deep into domain logic instead of a typed DTO | [details](references/ambiguous-map-to-domain.md) |

## Confidence Mapping

Boundary violations are largely structural facts (a grep-able import line), so confidence runs
high for the import-shape rules. The wire-parse rules require judgment because the right fix may
be "a typed DTO should exist" rather than "use the existing generated type":

| Finding type | Typical confidence | Lane |
|---|---|---|
| Domain module importing infra directly (infra path in import) | high | Fix |
| Core taking a concrete infra value import (non-`type`-only) | medium | Analyze — side-effect/lifecycle check needed |
| Handler parsing wire into `Value`/ad-hoc map where a generated typed frame already exists | high | Fix |
| Handler parsing wire into `Value`/ad-hoc map where NO generated type exists yet | medium | Analyze — proposes adding a typed DTO (behavior-changing) |
| Ambiguous map/blob passed into domain logic (typed DTO exists) | medium | Analyze |
| Infra import in a test fixture or composition root | low | Skip — these are wiring sites, not violations |

## Output Format

Findings are produced by the gate-refactor scanner agent as structured items (see
`gate-refactor/SKILL.md` Phase 3 brief). Each finding cites `file:line`, the violated slug, and a
specific proposed change (or "needs analysis" for medium). Do not emit findings for the
explicitly exempted sites in each reference file's **Exceptions** section — opaque forwarding,
malformed-frame handlers, and composition-root wiring are legitimate raw/infra uses.

## Scope

Narrow per-subproject; over-broad globs produce false positives in lifecycle/adapter files:

- Applies to (domain/core paths only):
  - `app/lib/domain/**`
  - `cockpit/lib/**/domain/**` (narrow — NOT all of `cockpit/lib`)
  - `pi-extension/src/reachability/**` (except `*.test.ts`)
  - `pi-extension/src/mesh/**` (except `*.test.ts`)
  - `relay/src/protocol/**` non-generated authored modules (NOT `protocol/generated/**`)
- **Excluded as composition/lifecycle/adapter sites** (do NOT scan with `domain-imports-infra`;
  the wire-parse rules may still apply where noted):
  - `pi-extension/src/session/**` — `mesh_node.ts`, `bridge.ts`, `broker.ts`, `cwd_lock.ts`,
    `leader_election.ts`, `local_config.ts`, `global_config.ts`, `setup_wizard.ts` are
    lifecycle/adapter/composition code, not domain logic. A domain/ports split here is a design
    decision, not a refactor — route via feature design, not this library.
  - `relay/src/handlers/**` — handlers are boundary/adapter code; they legitimately import
    stores/registries/transport-facing types. Apply `ad-hoc-wire-parse` and
    `ambiguous-map-to-domain` here, but NOT `domain-imports-infra`.
- Does NOT apply to: composition roots (`pi-extension/src/index.ts`, app `main.dart`, cockpit
  module bindings), test fixtures (`*.test.ts`, `*_test.dart`, `relay/tests/**`, and
  `#[cfg(test)] mod tests` blocks inside production files), generated code
  (`protocol/generated/`, `*.g.dart`), and `site/**`
