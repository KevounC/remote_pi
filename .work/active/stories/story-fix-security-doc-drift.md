---
id: story-fix-security-doc-drift
kind: story
stage: done
tags: [docs, pi-extension, site, relay]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Fix security/trust-model documentation drift

Adversarial review found stale E2E and crypto-stack claims that contradict `PROTOCOL.md`.

## Scope

- Rewrite stale E2E claims in `site/README.md` and `pi-extension/README.md`.
- Clarify root `README.md` wording around "opaque ciphertext" so it cannot be mistaken for E2E.
- Replace stale `libsodium-wrappers` guidance in `pi-extension/CLAUDE.md` with current Ed25519/TLS/no-E2E posture.
- Update `PROTOCOL.md` / agent-tool docs around ACK `busy` semantics so current reliable-delivery behavior is clear.

## Acceptance Criteria

- [x] Grep for `end-to-end`, `E2E`, `Noise`, `libsodium`, and `busy` in durable docs; remaining occurrences are either historical with a rollback banner or match current trust model.
- [x] Public/user-facing copy does not claim app-layer E2E encryption.
- [x] Agent-facing docs match current dependencies and protocol semantics.

## Implementation notes

Changed files:

- `README.md` now says the relay forwards authenticated WebSocket envelopes over TLS and can see current plaintext envelope contents; removed the misleading "opaque ciphertext" phrasing.
- `site/README.md`, `site/src/app/terms/page.tsx`, and mesh tutorial copy now avoid current E2E claims and stale retry-on-busy guidance.
- `pi-extension/README.md` now states the relay can see plaintext envelopes, images are inline JSON payloads rather than an opaque E2E blob, and built-in protections are TLS plus Ed25519 authentication.
- `pi-extension/CLAUDE.md` now reflects current dependencies (`@noble/ed25519`, `@napi-rs/keyring`) and the no-app-layer-E2E posture instead of `libsodium-wrappers` guidance.
- `PROTOCOL.md` now describes relay-visible plaintext envelopes and current ACK semantics: `received | denied | timeout` for normal unicast delivery, with `busy` only as a legacy/defensive status.
- `.agents/skills/formal-rigor-stack/SKILL.md` now treats no-retry-on-busy as current protocol semantics rather than unresolved drift.

Verification:

- Verified dependency `feature-adversarial-codebase-review` is `stage: done`.
- Ran `rg -n "end-to-end|E2E|Noise|libsodium|busy|opaque ciphertext" README.md site pi-extension PROTOCOL.md .agents docs 2>/dev/null`; remaining durable-doc hits are no-E2E disclosures, future-roadmap E2E mentions, cron `skip_if_busy` docs, or no-retry-on-busy semantics. Source/test hits were inspected but not changed except site documentation pages, per story boundaries.
- Ran scoped durable-doc grep `rg -n "end-to-end|E2E|Noise|libsodium|busy|opaque ciphertext" README.md site/README.md site/src/app pi-extension/README.md pi-extension/CLAUDE.md pi-extension/skills PROTOCOL.md .agents docs 2>/dev/null`; remaining hits match current trust model or daemon busy/skip terminology.
- Ran `cd site && corepack pnpm lint`; passed after Corepack installed site dependencies (plain `pnpm lint` was unavailable because `pnpm` was not on PATH).

## Review (2026-06-28)

Verdict: Approve

Findings: None.
