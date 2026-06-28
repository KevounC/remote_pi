---
source_handle: remote-pi-relay-app-router
fetched: 2026-06-28
source_path: relay/src/lib.rs
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay app state and router

Paraphrased summary: `relay/src/lib.rs` defines the public modules, shared `AppState`, axum state extraction for mesh handlers, and the unified router for WebSocket, health, and mesh membership surfaces.

## Key passages

- `AppState` contains `registry`, `presence`, `rooms`, `mesh`, `mesh_auth`, and `metrics`, each as shared `Arc`-owned state passed into handlers.
- `impl FromRef<AppState> for Arc<MeshStore>` lets mesh handlers extract only the mesh store while the router keeps a single `AppState`.
- `build_router(state)` mounts `GET /` to `handlers::peer::ws_handler`, `GET /health` to a simple `OK` response, and `GET/POST /mesh/:owner_pk_hash` to mesh handlers.
- The router applies `DefaultBodyLimit::max(mesh::handler::MAX_BODY_BYTES)` and calls `.with_state(state)`.
- Comments say the router should be mounted with `app.into_make_service_with_connect_info::<SocketAddr>()` so the WebSocket handler can extract `ConnectInfo<SocketAddr>` for log spans.

## Structural metadata

- Source type: Rust source
- Path: `relay/src/lib.rs`
