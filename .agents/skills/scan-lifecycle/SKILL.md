---
name: scan-lifecycle
description: >
  Remote-Pi resource-teardown and state-convergence scan. Enforces that long-lived resources
  (WebSockets, subscriptions, timers, controllers, ViewModels) close on their lifecycle
  boundary; that Flutter async UI guards `BuildContext` after `await`; that Pi session
  context is not used stale after replacement; and that `working` state converges false on
  every exit path. Grounded in `.agents/rules/code-design.md` (Lifecycle ownership) and
  `.agents/rules/testing-integrity.md` (Async and lifecycle tests — this repo's highest-risk
  defect class). Auto-loads as a gate-refactor rule library via glob `scan-*/SKILL.md`.
allowed-tools: Read, Glob, Grep
---

# Lifecycle Scan

Scans the release bundle's changed files for resource-teardown and state-convergence defects —
the highest-risk class in this repo per `.agents/rules/testing-integrity.md`. Each rule has a
reference file with rationale, real file:line examples, and exceptions. Loaded by `gate-refactor`
when `gates_for_release` includes `refactor`.

findings-route: none

## Why this library is UNTAGGED

Every fix here changes observable behavior: adding a missing `cancel()`/`dispose()` changes when
resources release; adding a `mounted` guard changes whether post-await UI code runs; adding
`working = false` to an error path changes what the UI shows; re-capturing session context
changes which session is acted on. These are correctness bug fixes, not behavior-preserving
refactors. Per the gate-refactor contract the tagged route requires the black-box test to hold
for every rule's fix; that is not defensible here, so findings route through story/feature
design where the behavior change is designed explicitly. This matches SNC platform's posture
(all 8 scan libraries untagged).

## Rules

| Rule | Slug | What to check | Reference |
|------|------|---------------|-----------|
| Resource not disposed | `resource-no-dispose` | Long-lived resource (subscription/timer/controller/WebSocket/ViewModel) without cancel/dispose on its lifecycle boundary | [details](references/resource-no-dispose.md) |
| BuildContext after await | `buildcontext-after-await` | Flutter `BuildContext` used after `await` without a `mounted` guard | [details](references/buildcontext-after-await.md) |
| Stale session context | `stale-session-context` | Pi SDK `ExtensionContext` captured before `/new`/`/resume`/`/fork`/`/reload` and used after replacement | [details](references/stale-session-context.md) |
| Working state not converging | `working-state-not-converging` | `working`/`isWorking` flag not set false on every exit path (success/error/abort/compaction/reconnect/shutdown) | [details](references/working-state-not-converging.md) |
| Unguarded async fire-and-forget | `unguarded-async-void` | `async` function whose returned Future is never awaited/returned/voided, swallowing errors | [details](references/unguarded-async-void.md) |

## Confidence Mapping

| Finding type | Typical confidence | Lane |
|---|---|---|
| Resource field with no cancel/dispose call anywhere in the owning class | high | Fix |
| Resource disposed on success path but not on error/early-return path | high | Fix |
| `BuildContext` after `await` with no `mounted` check between them | high | Fix |
| Session context stored in a field and read across an await that may cross `/new` | medium | Analyze — needs control-flow proof |
| `working` set true but no false assignment on a visible error/cancel exit | high | Fix |
| `working` derived from a single status enum (correct pattern) | low | Skip — not a violation |
| `async` function called without await at a callsite | medium | Analyze |

## Output Format

Findings are produced by the gate-refactor scanner agent as structured items (see
`gate-refactor/SKILL.md` Phase 3 brief). Each finding cites `file:line`, the violated slug, and a
specific proposed change (or "needs analysis" for medium). Do not emit findings for the
explicitly exempted sites in each reference file's **Exceptions** section.

## Cross-rule delineation (avoid double-counting)

The same async defect can look like several rules at once. Report it under exactly one rule,
the most specific:

- An **owner that never cancels a resource field** → `resource-no-dispose` (the teardown gap is
  the root cause).
- A **post-await use of `BuildContext` without a guard** → `buildcontext-after-await` (the missing
  guard is the root cause, even if the call was fire-and-forget).
- An **async call whose Future is discarded** with no `await`/`return`/`unawaited`/`void` →
  `unguarded-async-void` (the discarded Future is the root cause), UNLESS it leads to a
  post-await context use or a leaked resource, in which case the more specific rule above wins.
- A **`working`/turn status stuck true** → `working-state-not-converging` (independent of the
  above; a convergence bug is its own defect).
- A **session context used stale** → `stale-session-context` (pi-extension only).

Do not emit two findings for the same `file:line` under two of these rules; pick the most
specific per the ordering above.

## Scope

- Applies to:
  - `app/lib/**` (except `_test.dart`)
  - `cockpit/lib/**` (except `_test.dart`)
  - `pi-extension/src/**` (except `*.test.ts`)
  - `relay/src/**` (except `relay/tests/**` and `#[cfg(test)]` blocks)
- Does NOT apply to: test files, generated code (`protocol/generated/`, `*.g.dart`), `site/**`
