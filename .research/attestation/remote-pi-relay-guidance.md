---
source_handle: remote-pi-relay-guidance
fetched: 2026-06-28
source_path: relay/CLAUDE.md
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay local guidance

Paraphrased summary: `relay/CLAUDE.md` defines the relay as a stateless Rust WebSocket server that pairs connections by `peer_id`, routes ciphertext between app and pi-extension, and must never decrypt or log payload content.

## Key passages

- The relay is described as a stateless WebSocket server that pairs connections by `peer_id` and routes ciphertext between the app and pi-extension.
- Stack guidance names Rust 1.94+ / edition 2024, Tokio full, `tokio-tungstenite`, `serde`/`serde_json`, and `tracing`/`tracing-subscriber`.
- Commands listed include `cargo build`, `cargo run`, `RUST_LOG=info cargo run`, `cargo clippy -- -D warnings`, `cargo fmt`, and `cargo test`.
- Conventions say `anyhow::Result<()>` belongs at `main`, `thiserror::Error` belongs in internal libraries, async work uses `tokio::spawn`/`tokio::select!`, and production paths should not use `unwrap()`.
- Security policy says the relay never decrypts payload, visible metadata is limited to `peer_id`, size, and timestamp, logs must not contain payload even ciphertext, and rate limiting should be per `peer_id` and source IP.

## Structural metadata

- Source type: local subproject guidance
- Path: `relay/CLAUDE.md`
