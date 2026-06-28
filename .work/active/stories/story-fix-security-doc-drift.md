---
id: story-fix-security-doc-drift
kind: story
stage: implementing
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

- [ ] Grep for `end-to-end`, `E2E`, `Noise`, `libsodium`, and `busy` in durable docs; remaining occurrences are either historical with a rollback banner or match current trust model.
- [ ] Public/user-facing copy does not claim app-layer E2E encryption.
- [ ] Agent-facing docs match current dependencies and protocol semantics.
