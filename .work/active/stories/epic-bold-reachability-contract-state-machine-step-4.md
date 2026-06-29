---
id: epic-bold-reachability-contract-state-machine-step-4
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-reachability-contract-state-machine
depends_on: [epic-bold-reachability-contract-state-machine-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 4: Add the Rust Reachability projection module for relay heartbeat policy

**Priority**: Medium
**Risk**: Low
**Source Lens**: missing abstraction / naming inconsistency
**Files**: `relay/src/reachability.rs`, `relay/src/lib.rs`, `relay/src/handlers/peer.rs`, `relay/tests` or unit tests in `reachability.rs`

## Current State

The relay owns the WS heartbeat cadence inline in the peer handler:

```rust
// relay/src/handlers/peer.rs
// Send a WS Ping every 25 s so NAT/LB idle timers don't close the connection.
let mut heartbeat = time::interval_at(
    time::Instant::now() + Duration::from_secs(25),
    Duration::from_secs(25),
);
```

It has no named representation of the shared Reachability contract, so the 25s heartbeat is disconnected from the app's 25s protocol ping and the extension's 70s liveness watchdog.

## Target State

Add a small relay projection module and use it only for heartbeat cadence:

```rust
// relay/src/reachability.rs
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReachabilityState {
    Connecting,
    Online,
    Degraded,
    Offline,
    Retrying,
}

pub const REACHABILITY_BACKOFF: [Duration; 5] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(5),
    Duration::from_secs(10),
    Duration::from_secs(30),
];

pub fn reachability_backoff(attempt: usize) -> Duration {
    REACHABILITY_BACKOFF[attempt.min(REACHABILITY_BACKOFF.len() - 1)]
}

pub const RELAY_WS_PING_INTERVAL: Duration = Duration::from_secs(25);
pub const APP_PROTOCOL_PING_INTERVAL: Duration = Duration::from_secs(25);
pub const EXTENSION_LIVENESS_CHECK_INTERVAL: Duration = Duration::from_secs(20);
pub const EXTENSION_LIVENESS_TIMEOUT: Duration = Duration::from_secs(70);
pub const DEGRADED_AFTER_MISSED_APP_PONGS: u8 = 3;
```

Then in `relay/src/handlers/peer.rs`:

```rust
use crate::reachability::RELAY_WS_PING_INTERVAL;

let mut heartbeat = time::interval_at(
    time::Instant::now() + RELAY_WS_PING_INTERVAL,
    RELAY_WS_PING_INTERVAL,
);
```

## Implementation Notes

- Keep relay responsibility narrow: the relay uses only the WS heartbeat constant today; it does not infer app/Pi `Degraded` or session state.
- Export `pub mod reachability;` from `relay/src/lib.rs`.
- Add tests that compare the Rust projection against `protocol/schema/reachability.json` where practical. If JSON parsing in unit tests is awkward, at minimum assert all state variants, backoff clamp behavior, and heartbeat constants; note in implementation notes why full artifact comparison was deferred.
- Do not add durable relay session state or offline queue.

## Acceptance Criteria

- [x] `cargo fmt --check` passes from `relay/`.
- [x] `cargo test reachability` (or nearest filter) passes from `relay/`.
- [x] The relay heartbeat interval in `handlers/peer.rs` comes from `reachability.rs`.
- [x] Relay behavior remains the same: first ping after 25s, then every 25s.
- [x] The relay does not attempt to classify app/Pi `Degraded` state.

## Risk

Low. This changes a named constant source for an existing 25s interval. Behavior risk is limited to accidentally changing first-tick timing or interval duration.

## Rollback

Inline `Duration::from_secs(25)` in `handlers/peer.rs` again and delete `relay/src/reachability.rs` plus tests.

## Implementation notes

- Added `relay/src/reachability.rs` with the five-state enum, wire-name projection, shared backoff policy, heartbeat/liveness constants, and a clamped backoff helper.
- Exported `pub mod reachability;` from `relay/src/lib.rs` and changed the peer WebSocket heartbeat to use `RELAY_WS_PING_INTERVAL`, preserving first tick after 25s and repeat interval of 25s.
- Kept relay semantics narrow: the relay only consumes the WS ping constant; it does not infer app/Pi degraded state, session state, or offline queue semantics.
- Tests compare the Rust projection against `protocol/schema/reachability.json` for states, backoff seconds, and heartbeat fields.
- Verification run from `relay/`: `cargo fmt --check`, `cargo test reachability`, and `cargo clippy -- -D warnings` all passed.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane substrate review. Inspected commit `8c255aa`; relay heartbeat now imports `RELAY_WS_PING_INTERVAL` and keeps the first tick/repeat interval at 25s. Relay only consumes the WS ping constant and does not infer degraded/session/offline-queue state. Verification run from `relay/`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed.
