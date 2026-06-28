---
source_handle: remote-pi-broker-remote
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/pi-extension/src/session/broker_remote.ts
provenance: source-direct
---

# Remote Pi cross-PC broker remote

Paraphrased summary: `BrokerRemote` bridges the local UDS broker to sibling Pi instances over the relay. It routes outbound envelopes by `<pc>:` prefix, rewrites local sender addresses with the current PC label, maintains a TTL cache of sibling peer inventories, periodically re-announces to keep caches warm, and anti-spoofs inbound relay envelopes against sibling membership.

## Key passages

- The file-level comment describes outbound routing to known `<pc>:` prefixes and inbound handling from verified `from_pc` values.
- Inbound `handleIncoming` maps `fromPc` through the authoritative sibling pubkey-to-label map; unknown pubkeys are dropped.
- Inbound anti-spoof checks compare the prefix in `envelope.from` against the sibling label derived from `fromPc`; mismatches are dropped.
- `peers_update` and `peers_request` control envelopes update or query sibling peer inventories; normal envelopes have self prefixes stripped before local broker injection.
- ACK envelopes are generated for non-ACK remote injections so cross-PC senders can resolve delivery status.

## Structural metadata

- Source type: TypeScript source
- Path: `/home/agent/forks/remote_pi/pi-extension/src/session/broker_remote.ts`
