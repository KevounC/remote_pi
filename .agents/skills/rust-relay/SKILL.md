---
name: rust-relay
description: Remote Pi Rust relay reference. Read before editing or reviewing relay/ code, WebSocket routing, mesh membership endpoints, presence/rooms state, relay logging/privacy, cross-PC forwarding, or relay tests.
updated: 2026-06-28
provenance: skill-reference
---

# Rust Relay Reference

> Local scope: `relay/`
> Versions/context: Rust 2024 crate, `tokio` 1.52.x, `axum` 0.7.x with `ws`, `serde`/`serde_json`, `ed25519-dalek` 2.2.x, `rusqlite` 0.32.x with bundled SQLite, `tracing`/`tracing-subscriber`, and `tokio-tungstenite` in tests. [remote-pi-relay-cargo]{1}
> Canonical local docs: `relay/CLAUDE.md`, `relay/README.md`, `PROTOCOL.md`.

## When to load

- Any edit or review under `relay/`.
- Any change involving WebSocket handshake/routing, presence, rooms, room metadata, `working` state, mesh membership, cross-PC `pi_envelope` forwarding, relay logs/metrics, or relay privacy/security claims.
- Any change that touches protocol compatibility with `app/` or `pi-extension/`.

## Commands

Run from `relay/`: [remote-pi-relay-guidance]{1}

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
cargo build
RUST_LOG=info cargo run
```

Use `cargo fmt` to apply formatting. Do not commit `target/`, local databases under `data/`, secrets, or deployment-local logs.

## Relay responsibility boundaries

Remote Pi's relay is a transport and coordination service, not the owner of Pi session semantics:

- It authenticates peers with Ed25519 challenge-response, derives peer IDs from public keys, and routes WebSocket frames between live peers. [remote-pi-relay-router-handler]{1}
- It forwards outer-envelope `ct` values opaquely: parse JSON shape, enforce size, rewrite sender peer/room, and never decode or inspect payload content. [remote-pi-relay-outer-envelope]{1} [remote-pi-relay-router-handler]{1}
- It stores Owner-signed mesh membership blobs and verifies signatures/version monotonicity, but the Owner-signed blob remains the authority for membership. [remote-pi-relay-protocol]{1} [remote-pi-relay-mesh-auth]{1}
- It reports transport failures (`offline`, `not_authorized`, `bad_envelope`) as `_relay` envelopes correlated with the original message id, matching `PROTOCOL.md`. [remote-pi-relay-protocol]{1} [remote-pi-relay-mesh-auth]{1}
- It does **not** currently provide end-to-end encryption. `PROTOCOL.md` explicitly says TLS protects transport, but the relay operator can read current plaintext envelope contents; do not claim E2E in relay docs or copy unless the protocol changes. [remote-pi-relay-protocol]{1}

## Runtime and router shape

`relay/src/main.rs` is the composition root: it creates `Arc` owners for mesh storage, presence, rooms, metrics, peer registry, and mesh auth cache, then serves the router with Ctrl-C graceful shutdown. [remote-pi-relay-runtime]{1}

```rust
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();
    let state = relay::AppState { /* Arc-owned managers */ };
    let app = relay::build_router(state);
    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(async {
            if let Err(err) = tokio::signal::ctrl_c().await {
                tracing::error!(%err, "failed to install ctrl_c handler");
            }
        })
        .await?;
    Ok(())
}
```

Guidance:

- Keep `anyhow::Result<()>` at binary boundaries; use `thiserror::Error` for internal domain errors. [remote-pi-relay-guidance]{1}
- Keep routers thin: `build_router` mounts `GET /` for WebSocket, `GET /health`, and `GET/POST /mesh/:owner_pk_hash`; shared mutable services live in `AppState`. [remote-pi-relay-app-router]{1}
- Avoid `std::thread`; stay in Tokio tasks/timers/channels for async runtime work. [remote-pi-relay-guidance]{1}

## WebSocket handler pattern

Axum 0.7's `WebSocketUpgrade` establishes a WebSocket and `on_upgrade` transfers control to the async connection owner. [axum-0-7-websocket]{1} In Remote Pi, `handle_peer` owns one socket for its full lifetime. [remote-pi-relay-router-handler]{1}

Connection flow:

1. Wait up to `HELLO_TIMEOUT_MS` for `hello`.
2. Send a random nonce challenge.
3. Verify `auth` signature.
4. Register `(peer_id, room_id, sender)` in `PeerRegistry`.
5. Run a `tokio::select!` loop over inbound frames, outbound registry messages, and heartbeat pings.
6. On exit, unregister and clean room subscriptions. [remote-pi-relay-router-handler]{1}

Tokio `select!` cancels non-winning branches, so only use cancellation-safe operations in long-lived loops. Tokio documents `mpsc::Receiver::recv` and `UnboundedReceiver::recv` as cancellation-safe. [tokio-1-52-select-mpsc]{1}

Axum auto-responds to incoming WebSocket pings, but the relay still sends explicit outbound pings every 25 seconds for NAT/LB liveness. [axum-0-7-websocket]{1} [remote-pi-relay-router-handler]{1}

## Channels and backpressure

`PeerRegistry` stores `tokio::sync::mpsc::UnboundedSender<Message>` values for live connections. [remote-pi-relay-registry-presence-rooms]{1} Tokio documents unbounded channels as memory-bounded only by process memory; a slow receiver can cause arbitrary buffering and eventual process abort. [tokio-1-52-select-mpsc]{1}

Review implication {inferred: current registry senders are unbounded and Tokio documents unbounded memory growth}: any new high-volume broadcast path must either remain bounded by existing dedup/state-change rules or introduce explicit backpressure/drop semantics. Do not add a firehose producer that can enqueue unbounded messages per peer without a suppression rule.

## Presence, rooms, and `working` state

`PeerRegistry` is the relay's live state owner:

- Keys are `(peer_id, room_id)`; multiple live connections may share the same key for multi-device Owners. [remote-pi-relay-registry-presence-rooms]{1}
- `room_announced` fires only when the first connection for a room appears; `room_ended` fires only when the last connection for that room disappears. [remote-pi-relay-registry-presence-rooms]{1}
- `peer_online` fires only on offline→online, and `peer_offline` only when the peer has no remaining rooms. [remote-pi-relay-registry-presence-rooms]{1}
- Presence and rooms subscriptions replace the full subscription list on subscribe and are cleaned on disconnect. [remote-pi-relay-registry-presence-rooms]{1}

`RoomMeta.working` is serialized as a required boolean. `room_meta_update` uses merge-patch semantics: absent fields leave current metadata unchanged, nullable strings can be cleared with explicit `null`, and `working` changes only when a boolean is present. [remote-pi-relay-registry-presence-rooms]{1} [remote-pi-relay-router-handler]{1}

Cross-cutting rule {inferred: relay publishes `working` but does not infer turn completion}: every `working: true` path in app/extension behavior still needs convergence to `false` after success, error, abort, reconnect, and session replacement. The relay preserves and publishes state; it does not infer turn completion.

## Mesh membership and cross-PC forwarding

Mesh storage is intentionally narrow:

- `POST /mesh/:owner_pk_hash` accepts base64 `blob` + `sig`, verifies the Owner signature, checks URL hash consistency, caps bodies at 500 KiB, and stores only strictly newer versions. [remote-pi-relay-mesh-auth]{1}
- `GET /mesh/:owner_pk_hash` returns the stored blob/signature/version/timestamp or `304 Not Modified` when `since` is current enough. [remote-pi-relay-mesh-auth]{1}
- `verify_envelope()` verifies the exact received blob bytes; clients are responsible for canonical JSON before signing. [remote-pi-relay-mesh-auth]{1}
- `ed25519-dalek` 2.2 exposes `VerifyingKey::verify_strict`, which performs stricter signature verification including weak-key protections. [ed25519-dalek-2-2-verifying-key]{1}

Cross-PC forwarding (`pi_envelope`) uses the authenticated sender peer id as ground truth. Positive mesh sibling lookups are cached for 60 seconds; negative lookups are not cached so newly published membership can take effect on the next attempt. [remote-pi-relay-mesh-auth]{1}

Do not move broker-side anti-spoof rules into the relay by reading human-readable `envelope.from`; `PROTOCOL.md` assigns prefix/label anti-spoof validation to the receiving broker after the relay delivers `from_pc`. [remote-pi-relay-protocol]{1}

## SQLite and storage

`MeshStore` wraps a rusqlite `Connection` in a `std::sync::Mutex`, applies the schema idempotently, and runs monotonic upserts inside a transaction. [remote-pi-relay-mesh-auth]{1} Rusqlite's `Connection` exposes `transaction`, `query_row`, and `execute_batch`; `OptionalExtension` is used for no-row-as-`None` query patterns. [rusqlite-0-32-connection]{1}

Rules:

- Keep payload storage out of SQLite. Only signed mesh membership belongs in relay persistence. [remote-pi-relay-protocol]{1}
- Preserve monotonic-version rejection for mesh updates.
- If adding DB access in async handlers, keep lock scope small and avoid holding blocking SQLite work across unrelated async awaits.

## Logging, metrics, and privacy

Use `tracing` macros, not `println!`. `tracing_subscriber::fmt::init()` installs a subscriber and, with `env-filter`, uses `RUST_LOG` for filtering; Remote Pi enables `env-filter`. [tracing-subscriber-0-3-fmt-init]{1}

Privacy constraints:

- Never log `ct`, inner envelope bodies, app prompts, agent output, signatures, or raw mesh blobs.
- Prefer shortened peer tails, room ids, frame type names, byte counts, and coarse reasons.
- Relay guidance says logs must not contain payload even if ciphertext. [remote-pi-relay-guidance]{1}
- Metrics should remain aggregate counters like the existing firehose emitted/suppressed window, not per-message content records. [remote-pi-relay-registry-presence-rooms]{1}

## Validation boundaries

Validate untrusted data at the first relay boundary:

- Auth frames: parse tagged JSON and reject bad pubkeys, signatures, wrong message types, and timeout. [remote-pi-relay-router-handler]{1}
- Control frames: inspect `type`, parse expected arrays/objects conservatively, warn/drop unknown types. [remote-pi-relay-router-handler]{1}
- Outer envelopes: deserialize into `OuterEnvelope`, apply size ceiling, and keep `ct` opaque. [remote-pi-relay-outer-envelope]{1}
- Mesh endpoints: body cap, base64 decode, Owner signature verify, URL-hash match, monotonic version. [remote-pi-relay-mesh-auth]{1}

Do not pass raw `serde_json::Value` deep into new business logic unless the boundary logic has narrowed it to a small internal type.

## Anti-patterns

- Claiming the relay is E2E encrypted today.
- Logging payloads, ciphertext, raw inner envelopes, signatures, or full mesh blobs.
- Adding durable payload/session queues to the relay; offline queuing belongs elsewhere unless the protocol is redesigned.
- Treating `room_meta_update` omission as clear; omission means preserve, `working: false` clears working.
- Emitting presence/rooms updates on every reconnect without dedup/state-change semantics.
- Adding unbounded broadcast producers without a suppression/backpressure strategy.
- Using `unwrap()`/`expect()` on production input or I/O paths; reserve infallible serialization asserts for values the program just constructed.

## Review checklist

- Protocol/security: Does the change preserve relay opacity, no-E2E honesty, mesh authorization, and transport-error shapes from `PROTOCOL.md`?
- Lifecycle: Is each long-lived socket/channel/task owned and cleaned on disconnect or shutdown?
- State convergence: Do rooms/presence/working states converge after disconnect, reconnect, multi-device attach, and room/session replacement?
- Privacy: Are logs/metrics content-free and structured with `tracing`?
- Backpressure: Could a slow peer or high-volume event stream create unbounded memory growth?
- Tests: Are auth, routing, mesh, presence/rooms, and error paths covered with deterministic integration/unit tests?
