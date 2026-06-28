---
source_handle: remote-pi-relay-cargo
fetched: 2026-06-28
source_path: relay/Cargo.toml
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay Cargo manifest

Paraphrased summary: `relay/Cargo.toml` pins the relay as a Rust 2024 crate with the runtime, WebSocket, JSON, crypto, SQLite, tracing, and test dependencies that shape the relay reference.

## Key passages

- Package metadata declares `name = "relay"`, version `0.2.2`, and `edition = "2024"`.
- Runtime and server dependencies include `tokio = { version = "1.52.3", features = ["full"] }` and `axum = { version = "0.7.9", features = ["ws"] }`.
- Message/data dependencies include `serde` with `derive`, `serde_json`, `base64`, `sha2`, `ed25519-dalek = "2.2.0"`, and `rusqlite = { version = "0.32", features = ["bundled"] }`.
- Error/logging dependencies include `anyhow`, `thiserror`, `tracing`, and `tracing-subscriber` with `env-filter`.
- Dev/test dependencies include `reqwest`, `tempfile`, and `tokio-tungstenite`.

## Structural metadata

- Source type: local Cargo manifest
- Path: `relay/Cargo.toml`
