---
source_handle: ed25519-dalek-2-2-verifying-key
fetched: 2026-06-28
source_url: https://docs.rs/ed25519-dalek/2.2.0/ed25519_dalek/struct.VerifyingKey.html
provenance: source-direct
substrate_confidence: source-direct
---

# ed25519-dalek 2.2 VerifyingKey

Paraphrased summary: `ed25519-dalek` 2.2 provides `VerifyingKey` for Ed25519 public-key verification, including strict verification APIs that add weak-key checks.

## Key passages

- `VerifyingKey` is documented as an Ed25519 public key.
- The API includes `from_bytes`, `to_bytes`, `is_weak`, `verify`, and `verify_strict` methods.
- The crate documentation describes `verify_strict` as a way to avoid weak-key forgery scenarios by performing extra public-key checks.
- `verify_strict(&self, message: &[u8], signature: &Signature)` returns `Ok(())` only when a signature is valid for the message and key.

## Structural metadata

- Source type: docs.rs API docs
- URL: `https://docs.rs/ed25519-dalek/2.2.0/ed25519_dalek/struct.VerifyingKey.html`
