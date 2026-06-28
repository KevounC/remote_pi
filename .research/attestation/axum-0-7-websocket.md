---
source_handle: axum-0-7-websocket
fetched: 2026-06-28
source_url: https://docs.rs/axum/0.7.9/axum/extract/ws/struct.WebSocketUpgrade.html
provenance: source-direct
substrate_confidence: source-direct
---

# Axum 0.7 WebSocket APIs

Paraphrased summary: Axum 0.7's WebSocket extraction surface upgrades HTTP requests to bidirectional WebSocket connections and represents WebSocket frames with the `Message` enum.

## Key passages

- `WebSocketUpgrade` is the extractor for establishing WebSocket connections and exposes `on_upgrade` to continue with an upgraded socket.
- `axum::extract::ws::Message` includes text, binary, ping, pong, and close variants.
- `Message::Ping` carries a payload under 125 bytes, and the docs state ping messages are automatically responded to by the server.
- `Message::Pong` is automatically sent to the client if a ping message is received.

## Structural metadata

- Source type: docs.rs API docs
- URLs consulted:
  - `https://docs.rs/axum/0.7.9/axum/extract/ws/struct.WebSocketUpgrade.html`
  - `https://docs.rs/axum/0.7.9/axum/extract/ws/enum.Message.html`
