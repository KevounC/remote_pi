---
source_handle: local-remote-pi-readme
fetched: 2026-06-28
source_path: README.md
provenance: source-direct
---

# README.md attestation

1. Remote Pi is described as a way to control the Pi coding agent from a phone, pairing with a one-time QR code and chatting with a local agent while away from the computer.
2. The repository packages are: `app/` Flutter iOS/Android mobile client; `pi-extension/` Node + TypeScript Pi extension; `relay/` Rust + Tokio stateless WebSocket relay; `site/` NextJS landing/legal site.
3. The architecture diagram places Flutter app and Pi extension on WebSocket connections to a Rust relay, with the extension connected to a local Pi process and a local UDS broker for other agents.
4. Security/current-state note: pairing uses Ed25519 authentication and TLS in transit, but the relay can see message contents today; payloads are not end-to-end encrypted in the current version.
5. Local agent mesh discovery uses a Unix Domain Socket broker managed by the extension; exposed tools include `agent_send` and deprecated/request-style `agent_request`.
