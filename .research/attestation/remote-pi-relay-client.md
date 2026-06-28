---
source_handle: remote-pi-relay-client
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/pi-extension/src/transport/relay_client.ts
provenance: source-direct
---

# Remote Pi relay client

Paraphrased summary: `RelayClient` is the extension-side WebSocket transport. It opens a `ws` connection to the configured relay, authenticates with an Ed25519 challenge flow, sends control frames best-effort when connected, and uses a liveness watchdog so a quiet relay connection is closed and retried rather than treated as alive forever.

## Key passages

- `RelayClient` creates a `WebSocket` using `toWebSocketUrl(relayUrl)`, so persisted/configured HTTP(S) URLs are converted only when opening the transport.
- Authentication sends `hello` with public key and optional room metadata, receives a `challenge` nonce, signs it, and sends `auth` with the signature.
- The liveness timeout constant is 70 seconds; comments indicate relay pings are expected to arrive more frequently to keep the connection alive.
- `sendControl()` checks connection state and is best-effort/no-op when the socket is unavailable.
- Room-open errors and reconnect handling are explicit transport concerns; callers must not assume a control message was delivered when the WebSocket is closed.

## Structural metadata

- Source type: TypeScript source
- Path: `/home/agent/forks/remote_pi/pi-extension/src/transport/relay_client.ts`
