---
source_handle: remote-pi-relay-mesh-auth
fetched: 2026-06-28
source_path: relay/src/mesh/verify.rs
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay mesh auth and storage

Paraphrased summary: The relay mesh modules decode Owner-signed mesh envelopes, verify signatures over exactly received bytes, store monotonic versions in SQLite, expose `/mesh/:owner_pk_hash`, and authorize Pi-to-Pi forwarding from stored membership blobs.

## Key passages

- `verify_envelope()` parses the signed blob header, decodes `owner_pk`, builds an Ed25519 `VerifyingKey`, and calls `verify_strict(&env.blob, &sig)`; comments state clients, not the relay, are responsible for canonical JSON bytes.
- `post_mesh` caps request bodies at 500 KiB, decodes base64 blob/signature, verifies the Owner signature, checks the URL hash against `sha256(owner_pk)`, and stores only strictly newer versions.
- `get_mesh` returns `404` when no record exists and `304 Not Modified` when a `since` query parameter is present and the stored version is not newer.
- `MeshStore::open()` opens or creates the SQLite database, creates the parent directory when needed, and applies the included schema with `execute_batch`, making schema setup idempotent at open time.
- `MeshStore` wraps `rusqlite::Connection` in a `std::sync::Mutex`.
- `MeshStore::upsert()` runs inside a rusqlite transaction, rejects `new_version <= current`, and performs an UPSERT for `owner_pk_hash`, `owner_pk`, version, blob, sig, and timestamp.
- `MeshAuthCache` maps Pi pubkey to a set of mesh siblings, has a 60-second positive-cache TTL, does not cache negative lookups, and scans stored mesh blobs to authorize `pi_envelope` forwarding.
- `handle_pi_envelope()` requires `to_pc` and object `envelope`, rejects unauthorized pairs as `not_authorized`, forwards authorized frames as `pi_envelope_in`, and returns `offline` when the destination peer has no live registry connection.

## Structural metadata

- Source type: Rust source set
- Paths: `relay/src/mesh/{handler,store,types,verify}.rs`, `relay/src/handlers/pi_forward.rs`
