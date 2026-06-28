---
slug: rust-relay-skill-base
created: 2026-06-28
provenance: synthesis
---

# Rust relay skill-base brief

## Registration summary

- Commissioning item: `story-api-reference-rust-relay-stack`.
- Scope authority: mixed.
- Verification rigor: standard.
- Decision relevance: determine the durable relay reference that agents must load before editing `relay/`, especially for async WebSocket routing, stateless/opaque relay boundaries, mesh membership, privacy-preserving logging, and protocol-compatible transport errors.
- Output kind: skill-reference.

## Decomposition rationale

I considered three engagement shapes:

1. **Single API reference only** — fast crate-doc summary for Tokio/Axum/Serde/tracing, but too weak on Remote Pi's relay-specific state and security boundaries.
2. **Local-code-only relay guide** — strong on actual implementation, but risks stale API assumptions for Axum WebSocket ping behavior, Tokio `select!` cancellation, `ed25519-dalek` strict verification, rusqlite transaction/optional APIs, and tracing subscriber filtering.
3. **Hybrid skill-reference pass** — local code/protocol as the primary substrate, with version-pinned external docs only for crate APIs that future agents are likely to touch.

I chose the hybrid pass. The declared item already named both local relay semantics and current API facts, so the local source decomposition was pre-registered while the exact external API checks were engagement-time judgment.

## Synthesis

The relay reference should center the relay's boundary: authenticate peers, route live WebSocket frames, maintain intentionally bounded presence/rooms/mesh state, and avoid becoming the source of Pi session truth. Local protocol docs assign current transport, mesh membership, transport-error, and no-E2E claims to `PROTOCOL.md`; the relay reference therefore warns agents not to claim end-to-end encryption and not to move broker-side anti-spoof checks into relay-side human-address parsing. [remote-pi-relay-protocol]{1}

The central local implementation facts for this reference are connection ownership and state convergence. `handle_peer` owns one WebSocket from hello/challenge/auth through registry registration, `tokio::select!` routing, heartbeat pings, and unregister cleanup. [remote-pi-relay-router-handler]{1} `PeerRegistry` permits multiple live connections per `(peer_id, room_id)`, emits room/presence transitions only on real state changes, and treats `RoomMeta.working` as required metadata that the relay publishes but does not infer. [remote-pi-relay-registry-presence-rooms]{1}

Version-sensitive API checks support those rules. Axum 0.7 provides `WebSocketUpgrade::on_upgrade` and `Message::{Text,Binary,Ping,Pong,Close}`, with ping/pong auto-response behavior. [axum-0-7-websocket]{1} Tokio 1.52 documents `select!` branch cancellation and cancellation-safe mpsc receives; it also warns that unbounded channels can buffer arbitrarily until process memory is exhausted. [tokio-1-52-select-mpsc]{1} These two facts justify explicit handler lifecycle guidance plus a backpressure review check for any new high-volume broadcast path.

Mesh membership and crypto guidance should remain narrow. The relay verifies Owner-signed mesh blobs over exact bytes, stores monotonic SQLite versions, and caches positive sibling lookups for cross-PC forwarding. [remote-pi-relay-mesh-auth]{1} `ed25519-dalek` 2.2's `VerifyingKey::verify_strict` supports the strict Owner-signature check used by local code. [ed25519-dalek-2-2-verifying-key]{1} The reference therefore tells agents to preserve canonical-byte ownership in clients, monotonic-version rejection in the relay, and `_relay` transport-error envelope shapes.

## Outputs

- `.agents/skills/rust-relay/SKILL.md`
- `.research/attestation/remote-pi-relay-*.md` for local relay/protocol sources.
- `.research/attestation/{axum-0-7-websocket,tokio-1-52-select-mpsc,ed25519-dalek-2-2-verifying-key,rusqlite-0-32-connection,tracing-subscriber-0-3-fmt-init}.md` for version-sensitive crate/API facts.
- `AGENTS.md` and `relay/CLAUDE.md` links to the new reference.

## Contradictions

The main terminology tension is that local relay guidance calls the relay “stateless,” while current implementation intentionally stores mesh membership and holds live presence/room/connection state. [remote-pi-relay-guidance]{1} [remote-pi-relay-mesh-auth]{1} [remote-pi-relay-registry-presence-rooms]{1} The resolved wording in the skill is “transport/payload stateless and opaque, with intentionally bounded coordination state,” rather than a blanket claim that the relay has no state.

No direct contradiction was found between current crate docs and local implementation. A load-bearing design tension is operational: existing live-connection senders are unbounded mpsc channels, while Tokio warns unbounded channels can grow until process memory is exhausted. [tokio-1-52-select-mpsc]{1} [remote-pi-relay-registry-presence-rooms]{1} The skill resolves this as a review constraint for future high-volume paths, not as a claim that the current low-volume paths are wrong.

## Disconfirming analysis

I looked for evidence that the relay should be treated as an application/session authority rather than a routing/coordination layer. The canonical protocol points the opposite way: app actions, session state, and anti-spoof label checks live in app/pi-extension/broker layers, while the relay verifies membership and reports transport errors. [remote-pi-relay-protocol]{1}

I also checked whether current docs support treating Axum ping handling as manual-only or Tokio unbounded channels as safely backpressured. Axum documents automatic ping response behavior, and Tokio documents unbounded buffering with memory as the implicit bound. [axum-0-7-websocket]{1} [tokio-1-52-select-mpsc]{1}

## Verification plan

- Run ARD citation lint against this brief and the new skill reference.
- Run a spot-check over all citation handles in `.agents/skills/rust-relay/SKILL.md` to ensure each cited detail appears in the matching attestation.
- Run a standard-rigor adversarial read against the skill, brief, and attestations before closing `story-api-reference-rust-relay-stack`.
