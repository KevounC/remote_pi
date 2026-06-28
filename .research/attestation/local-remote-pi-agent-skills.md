---
source_handle: local-remote-pi-agent-skills
fetched: 2026-06-28
source_path: .agents/skills/flutter-mobile/SKILL.md, .agents/skills/pi-extension-typescript/SKILL.md, .agents/skills/rust-relay/SKILL.md, .agents/skills/mobile-remote-coding/SKILL.md
provenance: source-direct
---

# Agent skills attestation

1. The Flutter mobile reference says the app architecture is layered `ui -> domain <- data`, with `config`/`routing` composing dependencies; it emphasizes Provider/ViewModels, `go_router`, WebSocket reconnect, and async `BuildContext` mounted guards.
2. The mobile remote-coding checklist states mobile clients are not terminals with perfect continuity and should be designed as `authoritative snapshot + idempotent commands + replayable deltas + reconnect hydration`, not sticky booleans plus best-effort streams.
3. The Pi extension TypeScript reference states Node >=20, TypeScript 6.x, Pi SDK 0.79.x, `ws` 8.x, Vitest 4.x, ESM-only source, strict TypeScript, and lifecycle hooks for session start/shutdown, turn start/end, message streaming, and room metadata.
4. The Pi extension reference notes the source-local protocol codec is not currently the authoritative live runtime validation boundary; inbound dispatch still uses source-local parsing/dispatch.
5. The Rust relay reference states the relay authenticates peers, routes WebSocket frames, stores Owner-signed mesh membership, reports transport failures as `_relay` envelopes, and does not provide E2E encryption today.
6. The Rust relay reference warns that `PeerRegistry` uses unbounded Tokio mpsc senders, so new high-volume broadcast paths need bounded/deduplicated/backpressure semantics.
