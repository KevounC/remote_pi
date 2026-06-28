---
source_handle: tracing-subscriber-0-3-fmt-init
fetched: 2026-06-28
source_url: https://docs.rs/tracing-subscriber/0.3.23/tracing_subscriber/fmt/fn.init.html
provenance: source-direct
substrate_confidence: source-direct
---

# tracing-subscriber 0.3 fmt init

Paraphrased summary: `tracing_subscriber::fmt::init()` installs a global tracing subscriber, and with `env-filter` enabled it filters events from `RUST_LOG`.

## Key passages

- The docs describe `fmt::init()` as installing a global tracing subscriber that listens for events.
- The initialized subscriber filters based on the `RUST_LOG` environment variable.
- With the `env-filter` feature enabled, `fmt::init()` uses `EnvFilter`; Remote Pi enables this feature in `relay/Cargo.toml`.
- The relay should use `tracing` macros for structured logs rather than `println!` in production paths.

## Structural metadata

- Source type: docs.rs API docs plus local manifest cross-check
- URL: `https://docs.rs/tracing-subscriber/0.3.23/tracing_subscriber/fmt/fn.init.html`
