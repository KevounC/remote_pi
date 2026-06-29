---
id: story-fix-cross-pc-transport-error-uuid
kind: story
stage: done
tags: [relay, pi-extension, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: v0.5.0
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Fix cross-PC transport_error envelope IDs

Relay-synthesized cross-PC `transport_error` envelopes currently use a 32-character hex id that does not satisfy the local broker envelope UUID parser, so explicit `offline` / `not_authorized` errors can be dropped locally.

## Scope

- Generate UUID-shaped ids for relay-synthesized transport-error envelopes, or relax the local envelope parser only if that is the chosen protocol rule.
- Preserve `re` correlation with the original envelope id.

## Acceptance Criteria

- [x] Relay `offline`, `not_authorized`, and `bad_envelope` transport errors parse through `pi-extension/src/session/envelope.ts`.
- [x] Sender receives the explicit transport error reason instead of a generic timeout.
- [x] Add relay/extension coverage for at least the offline path.

## Implementation notes

- Files changed: `relay/src/handlers/pi_forward.rs`, `relay/tests/pi_forward_test.rs`, `pi-extension/src/session/envelope.test.ts`.
- Tests added: relay transport-error UUID-shape assertions for `offline`, `not_authorized`, and `bad_envelope`; pi-extension parser coverage for relay-shaped `transport_error` envelopes.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: `cd relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed; `cd pi-extension && corepack pnpm typecheck && corepack pnpm test -- src/session/envelope.test.ts` passed.

## Review (2026-06-28)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fresh-context review of commit `69943ad`; correctness, tests, security/privacy, design alignment, UUID parser compatibility, and foundation-doc drift lenses checked. Verification evidence from implementation notes accepted; tests were not re-run.
