---
source_handle: remote-pi-relay-protocol
fetched: 2026-06-28
source_path: PROTOCOL.md
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi protocol and relay responsibilities

Paraphrased summary: `PROTOCOL.md` is the canonical wire/security document for Remote Pi. It assigns the relay WebSocket transport, mesh membership verification, cross-PC forwarding, and failure-mode reporting while explicitly not claiming E2E encryption for current payloads.

## Key passages

- The 30-second overview says the relay routes ciphertext and stores Owner-signed `mesh_versions`; it verifies signatures but does not decide membership.
- Cross-PC routing uses `pi_envelope` and `pi_envelope_in` frames, with relay-side authorization checking that Pi-A and Pi-B are members of the same Owner mesh.
- Transport errors are normal envelopes from `_relay` whose body has `type: "transport_error"`, correlated by `re` to the original envelope id.
- Mesh membership is an Owner-signed `mesh_versions` blob with monotonic versioning, stored in SQLite and indexed by `owner_pk_hash = SHA256(owner_pk)`.
- The trust model explicitly says there is no current end-to-end encryption between app and pi-extension or between Pis cross-PC; TLS protects transport, but relay operators can read current plaintext envelope contents.
- Failure modes include immediate `transport_error: offline` when a destination Pi is offline and `transport_error: not_authorized` when Pis are in different Owners.

## Structural metadata

- Source type: local canonical protocol document
- Path: `PROTOCOL.md`
