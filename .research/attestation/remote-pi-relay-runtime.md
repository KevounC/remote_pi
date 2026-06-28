---
source_handle: remote-pi-relay-runtime
fetched: 2026-06-28
source_path: relay/src/main.rs
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay runtime entry point

Paraphrased summary: `relay/src/main.rs` wires the runtime, state owners, metrics reporter, router, TCP listener, and graceful shutdown for the relay binary.

## Key passages

- `#[tokio::main] async fn main() -> anyhow::Result<()>` is the binary boundary.
- `REMOTEPI_RELAY_PORT` defaults to `3000`; `REMOTEPI_MESH_DB_PATH` defaults to `data/mesh.db` for bare-metal runs.
- Startup reads and logs the effective outer-envelope size limit via `relay::protocol::outer::max_ct_bytes()`.
- Long-lived state owners are constructed as `Arc`: `MeshStore`, `PresenceManager`, `RoomManager`, `FirehoseMetrics`, `PeerRegistry`, and `MeshAuthCache`.
- A background Tokio task drains firehose metrics every 10 seconds and emits structured tracing logs only when there was activity.
- Serving uses `axum::serve(...).with_graceful_shutdown(...)` and awaits `tokio::signal::ctrl_c()` before shutdown.

## Structural metadata

- Source type: Rust source
- Path: `relay/src/main.rs`
