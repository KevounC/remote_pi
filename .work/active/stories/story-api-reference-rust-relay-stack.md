---
id: story-api-reference-rust-relay-stack
kind: story
stage: done
tags: [relay, research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
release_binding: null
gate_origin: null
research_dials:
  scope_authority: mixed
  verification_rigor: standard
  intent: rust-relay-api-reference
  output_kind: skill-reference
created: 2026-06-27
updated: 2026-06-28
research_refs: [rust-relay-skill-base]
---

# API reference for Rust relay stack

Create a platform-style stack reference for `relay/`, focused on async WebSocket routing, stateless relay guarantees, and observable-but-private operations.

## Candidate coverage

- Rust 2024 edition conventions relevant to this repo.
- Tokio task, channel, cancellation, and `select!` patterns.
- Axum WebSocket APIs and/or tokio-tungstenite usage actually present in the relay.
- Serde/serde_json message parsing, versioning, and validation boundaries.
- Tracing/tracing-subscriber spans and structured logging.
- Error handling with `anyhow` at binary boundaries and `thiserror` in internal libraries.
- Rusqlite use if relay state/version endpoints rely on SQLite.
- Crypto/signature dependencies (`ed25519-dalek`, `sha2`, `base64`) at protocol boundaries.
- Test/dev cycle: `cargo fmt`, `cargo clippy -- -D warnings`, `cargo test`, integration relay smoke.

## Known gotchas to include

- Relay must not decrypt or log payload content, even ciphertext bodies unless explicitly safe.
- Preserve stateless or intentionally bounded state semantics; stale peer/session behavior must be explicit.
- Delivery/ACK/timeout semantics should match `PROTOCOL.md` and app/pi-extension expectations.
- Rate limiting and metadata logging must not leak sensitive content.

## Implementation notes

- Ran the engagement through `research-orchestrator` with the registered dials: `scope_authority: mixed`, `verification_rigor: standard`, `intent: rust-relay-api-reference`, `output_kind: skill-reference`.
- Added synthesis brief `.research/analysis/briefs/rust-relay-skill-base.md` with decomposition rationale, contradictions, disconfirming analysis, outputs, and verification plan.
- Added durable reference `.agents/skills/rust-relay/SKILL.md` covering relay responsibilities, Tokio/Axum WebSocket lifecycle, channels/backpressure, presence/rooms/`working`, mesh membership/cross-PC forwarding, SQLite storage, tracing/privacy, validation boundaries, anti-patterns, commands, and review checklist.
- Added source attestations under `.research/attestation/` for relay local sources and version-sensitive crate docs: Axum WebSocket, Tokio `select!`/mpsc, `ed25519-dalek`, rusqlite, and `tracing-subscriber`.
- Linked the reference from `AGENTS.md` and `relay/CLAUDE.md`.
- Verification: ARD citation lint passed with `0 broken` and `0 thin` for both the synthesis brief and skill reference; remaining warnings are expected version-number flags in a versioned API reference. Standard-rigor adversarial read initially requested citation specificity fixes; after extending attestations, changing one citation, avoiding an `unwrap()` example, and marking composed guidance, the re-check verdict was `APPROVED`.

## Acceptance

- [x] A reference skill/doc exists and is linked from `AGENTS.md` or relay guidance.
- [x] It distinguishes app/pi-extension responsibilities from relay responsibilities.
- [x] It contains concrete API examples for WebSocket handling, tracing, error propagation, and tests.
