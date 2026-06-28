---
source_handle: tokio-1-52-select-mpsc
fetched: 2026-06-28
source_url: https://docs.rs/tokio/1.52.3/tokio/macro.select.html
provenance: source-direct
substrate_confidence: source-direct
---

# Tokio 1.52 select and unbounded mpsc

Paraphrased summary: Tokio's `select!` macro races multiple async branches, cancelling the non-selected branches, and Tokio's unbounded mpsc channel removes backpressure except for available process memory.

## Key passages

- `tokio::select!` waits on multiple concurrent branches, returns when the first branch completes, and cancels the remaining branches.
- The docs note cancellation safety matters in loops; `tokio::sync::mpsc::Receiver::recv` and `UnboundedReceiver::recv` are listed as cancellation safe.
- `tokio::sync::mpsc::unbounded_channel` creates an unbounded channel; sends succeed while the receiver is open.
- The unbounded-channel docs warn that if the receiver falls behind, messages are arbitrarily buffered, process memory is the implicit bound, and the process can run out of memory.

## Structural metadata

- Source type: docs.rs API docs
- URLs consulted:
  - `https://docs.rs/tokio/1.52.3/tokio/macro.select.html`
  - `https://docs.rs/tokio/1.52.3/tokio/sync/mpsc/fn.unbounded_channel.html`
