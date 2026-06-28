---
source_handle: remote-pi-relay-router-handler
fetched: 2026-06-28
source_path: relay/src/handlers/peer.rs
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay WebSocket router and peer handler

Paraphrased summary: `relay/src/handlers/peer.rs` owns one WebSocket connection through challenge/authentication, registry registration, control-frame handling, opaque outer-envelope forwarding, heartbeat pings, and unregister cleanup.

## Key passages

- `ws_handler` accepts an Axum `WebSocketUpgrade`, extracts the remote socket address, and calls `ws.on_upgrade(move |socket| handle_peer(...))`.
- The connection handshake waits up to `HELLO_TIMEOUT_MS` for a text `hello`, sends a nonce challenge, then verifies an `auth` signature before deriving `peer_id` from the Ed25519 verifying key bytes.
- Room metadata is read from the hello frame: `room_id` defaults to `main`, optional metadata includes `name`, `cwd`, `model`, `thinking`, and `working`, and `started_at` is set from local time.
- The routing loop uses `tokio::select!` over incoming WebSocket messages, registry outbound channel receives, and a 25-second heartbeat interval that sends Axum `Message::Ping(Vec::new())`.
- Top-level JSON frames with `type` are relay control frames: presence subscribe/unsubscribe/check, rooms subscribe/unsubscribe/check, `room_meta_update`, and `pi_envelope`.
- Frames without `type` are parsed as `OuterEnvelope`; the relay forwards them after rewriting sender `peer` and `room`, but does not inspect or decode `ct`.
- Invalid JSON/envelopes and unknown control frames are dropped with `tracing::warn!`; disconnect unregisters the connection and clears room subscriptions.

## Structural metadata

- Source type: Rust source
- Path: `relay/src/handlers/peer.rs`
