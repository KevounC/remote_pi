---
source_handle: local-remote-pi-protocol
fetched: 2026-06-28
source_path: PROTOCOL.md
provenance: source-direct
---

# PROTOCOL.md attestation

1. `PROTOCOL.md` frames Remote Pi as a mesh of coding agents across multiple PCs owned by one user, with each PC running a Node.js `pi-extension` daemon using an Ed25519 Pi-key and the mobile app acting as the initial authenticator.
2. It defines three identity classes: Owner-key on mobile keychain/sync storage, Pi-key in system keychain or `~/.pi/remote/identity.json` fallback, and ephemeral App-key during pairing.
3. It layers agent messages as: Agent layer, JSON envelope, routing by local UDS broker or cross-PC relay forwarding, ACK protocol, transport, and trust.
4. The envelope is a five-field JSON shape `{from,to,id,re,body}`, with cross-PC routing using a PC label prefix.
5. The document currently states ACK statuses include `received | busy | denied | timeout`, and says `busy` means a mid-turn peer discarded the message and the sender retries.
6. Mesh membership is an Owner-signed `mesh_versions` structure with monotonic versioning stored by relay in SQLite; relay verifies signatures but the Owner-signed blob is authority.
7. Cross-PC forwarding uses relay-side membership authorization and broker-side anti-spoofing based on authenticated `from_pc` and human-readable prefix consistency.
