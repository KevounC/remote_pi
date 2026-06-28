---
source_handle: remote-pi-relay-outer-envelope
fetched: 2026-06-28
source_path: relay/src/protocol/outer.rs
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi relay outer-envelope parser

Paraphrased summary: `relay/src/protocol/outer.rs` defines the relay's opaque outer envelope and validates only JSON shape plus configured ciphertext-size ceiling.

## Key passages

- `OuterEnvelope` has `peer`, `room`, and `ct`; `room` defaults to `main`; the comment on `ct` says it is base64 and never decoded here.
- `RELAY_MAX_CT_MIB` overrides the outer-envelope size ceiling; `DEFAULT_MAX_CT_MIB` is 4.
- `max_ct_bytes()` reads the environment once with `OnceLock`, accepts positive integer MiB values, and falls back to default without panicking on absent/invalid values.
- `parse_line()` deserializes JSON into `OuterEnvelope` and estimates decoded size as `env.ct.len() * 3 / 4`; it rejects values above the configured ceiling.
- Tests cover minimal envelopes, room defaulting, large-payload rejection, acceptance of roughly 2 MiB payloads under the 4 MiB default, and invalid JSON.

## Structural metadata

- Source type: Rust source
- Path: `relay/src/protocol/outer.rs`
