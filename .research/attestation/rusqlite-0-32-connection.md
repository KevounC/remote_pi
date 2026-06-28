---
source_handle: rusqlite-0-32-connection
fetched: 2026-06-28
source_url: https://docs.rs/rusqlite/0.32.1/rusqlite/struct.Connection.html
provenance: source-direct
substrate_confidence: source-direct
---

# rusqlite 0.32 Connection and OptionalExtension

Paraphrased summary: `rusqlite` exposes an ergonomic SQLite `Connection`, transactions, `query_row`, and `OptionalExtension` for converting no-row query results to `Option`.

## Key passages

- `Connection` is the primary database connection type and exposes methods including `transaction`, `query_row`, and `execute_batch`.
- `Connection::transaction()` returns a transaction and requires mutable access to the connection.
- The `OptionalExtension` trait is documented for adapting a rusqlite result to an optional value, allowing no-row cases to become `None`.
- Remote Pi enables rusqlite's `bundled` feature locally, so agents should not assume a system SQLite library is required for normal builds.

## Structural metadata

- Source type: docs.rs API docs plus local manifest cross-check
- URLs consulted:
  - `https://docs.rs/rusqlite/0.32.1/rusqlite/struct.Connection.html`
  - `https://docs.rs/rusqlite/0.32.1/rusqlite/trait.OptionalExtension.html`
