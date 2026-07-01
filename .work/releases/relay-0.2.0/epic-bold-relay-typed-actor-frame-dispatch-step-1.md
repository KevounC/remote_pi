---
id: epic-bold-relay-typed-actor-frame-dispatch-step-1
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-generated-protocol-rust-codegen]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 1: Introduce the typed relay frame decode boundary

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / generated contracts / fail-fast boundary  
**Files**: `relay/src/protocol/mod.rs`, `relay/src/protocol/frame.rs`, generated Rust protocol module from `epic-bold-generated-protocol-rust-codegen`, `relay/src/protocol/outer.rs`

## Current State

`handle_peer` parses every text frame into raw JSON first, branches on an optional string discriminator, and falls through to a second outer-envelope parse when no `type` exists:

```rust
let frame: serde_json::Value = match serde_json::from_str(&text) {
    Ok(v) => v,
    Err(e) => {
        warn!(peer = %peer_short, err = %e, "invalid json, dropping");
        continue;
    }
};

if let Some(t) = frame.get("type").and_then(|v| v.as_str()) {
    match t {
        "subscribe_presence" => { /* ... */ }
        "pi_envelope" => { /* ... */ }
        _ => warn!(peer = %peer_short, frame_type = %t, "unknown control frame type, dropping"),
    }
    continue;
}

match parse_line(&text) { /* OuterEnvelope path */ }
```

This spreads frame-shape validation through the connection loop and makes adding a relay-owned frame a string-match edit.

## Target State

Add one relay boundary module that consumes generated serde types and is the only place that classifies text frames:

```rust
// relay/src/protocol/frame.rs
use crate::protocol::generated::{
    OuterEnvelope, PiEnvelopeFrame, RelayControlFrame, RelayInboundFrame,
};

#[derive(Debug)]
pub enum DecodedRelayFrame {
    Outer(OuterEnvelope),
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
}

#[derive(Debug, thiserror::Error)]
pub enum FrameDecodeError {
    #[error("invalid json: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("unknown relay frame type: {0}")]
    UnknownType(String),
    #[error("outer envelope too large: {estimated} bytes (max {max})")]
    OuterTooLarge { estimated: usize, max: usize },
}

pub fn decode_relay_frame(text: &str) -> Result<DecodedRelayFrame, FrameDecodeError> {
    if has_type_discriminator(text)? {
        return match serde_json::from_str::<RelayInboundFrame>(text)? {
            RelayInboundFrame::Control(frame) => Ok(DecodedRelayFrame::Control(frame)),
            RelayInboundFrame::PiEnvelope(frame) => Ok(DecodedRelayFrame::PiEnvelope(frame)),
        };
    }

    Ok(DecodedRelayFrame::Outer(OuterEnvelope::parse_json(text)?))
}
```

`serde_json::Value` stays permissible only at the boundary where the generated parser or opaque cross-PC envelope requires it; the connection actor receives typed variants.

## Implementation Notes

- Do not design or hand-maintain the schema here. Import/re-export the generated Rust relay-owned frame types from the Rust codegen story.
- Preserve the current compatibility rule: no top-level `type` means app↔Pi outer envelope, and `room` defaults according to the generated/compat `OuterEnvelope` parser until canonical-session targeting changes that behavior.
- Preserve the existing `ct` size ceiling and error categories from `protocol/outer.rs`.
- Add focused unit tests for: invalid JSON drops; unknown typed frame drops; no-type outer envelope decodes; `ct` too large rejects; known control frame decodes into the expected typed variant.

## Acceptance Criteria

- [ ] `relay/src/protocol/frame.rs` is the single decode/classification boundary for inbound WebSocket text frames.
- [ ] The boundary consumes generated serde structs/enums for relay-owned frames instead of a new handwritten protocol mirror.
- [ ] Unknown or malformed frame input fails before connection dispatch.
- [ ] Outer payload opacity and size checks are preserved.
- [ ] `cargo fmt --check`, `cargo clippy -- -D warnings`, and targeted relay tests pass from `relay/`.

## Risk

Medium. The parsing seam is the highest-leverage part of the refactor; accidentally changing compatibility handling for no-`type` outer envelopes would be observable.

## Implementation

- Added `relay/src/protocol/frame.rs` as the inbound WebSocket text decode/classification boundary. The connection loop now calls `decode_relay_frame()` once and dispatches only `DecodedRelayFrame::{Control, PiEnvelope, Outer}` variants, with a compatibility `MalformedPiEnvelope` path retained solely to preserve existing `bad_envelope` transport-error correlation.
- Extended the Rust protocol generator to emit generated `protocol::generated::frame::RelayInboundFrame` and `RELAY_INBOUND_FRAME_TYPES`, then regenerated `relay/src/protocol/generated/{mod.rs,frame.rs}`. The boundary consumes generated `RelayControlFrame`, `PiEnvelopeFrame`, `OuterEnvelope`, and `RelayInboundFrame`; no handwritten protocol schema mirror was added.
- Fail-fast behavior: invalid JSON and unknown typed frames are rejected at the boundary before normal connection dispatch. Known malformed control frames are rejected by generated serde parsing. Malformed `pi_envelope` frames are classified at the boundary and routed only through the existing bad-envelope transport-error path to preserve protocol behavior.
- Outer envelope behavior: the boundary preserves the no-top-level-`type` outer-envelope path through `protocol::outer::parse_line()`, including opaque `ct`, the 4 MiB decoded-size ceiling, and `FrameDecodeError::OuterTooLarge` mapping from the existing `ParseError::TooLarge`. Current generated outer parsing remains fail-closed for missing `room`, matching the existing relay tests in this checkout.
- Focused tests added in `protocol::frame`: invalid JSON rejection, unknown typed-frame rejection, no-type outer-envelope decode, `ct` too large rejection, and known control-frame typed decode. Full relay verification passed: `cargo test` reported 81 lib tests, 3 integration tests, 13 mesh tests, 8 pi-forward tests, 10 presence tests, 2 protocol parity tests, and 19 rooms tests passing.
- Regeneration verdict: `node --check tools/protocol-codegen/bin/protocol-codegen.mjs`, Rust generated-protocol `--check`, determinism double-run (`diff -r` between two temp generations), and temp-generation diff against `relay/src/protocol/generated` all passed cleanly.

## Rollback

Revert `relay/src/protocol/frame.rs` and return the routing loop to its current inline parse path. Generated protocol artifacts can remain because this story only consumes them.

## Review

Approved (2026-06-30) with generated-contract + fail-fast verification.
Independently re-ran: regen `--check` pass; determinism double-run byte-identical;
committed generated files match generator output (no hand-edits). Relay
`cargo fmt --check` clean; `cargo clippy -- -D warnings` clean; `cargo test`
136 passed / 0 failed (81 lib + 3 integ + 13 mesh + 8 pi_forward + 10 presence +
2 protocol_parity + 19 rooms; +5 new frame-decode boundary tests). Commit
`2c9dbd3` scoped to protocol/frame.rs + generated/{frame,mod}.rs (via generator)
+ handlers/peer.rs (dispatch consumer) + generator + story .md.

Single decode/classification boundary verified: `decode_relay_frame()` returns
`DecodedRelayFrame::{Control, PiEnvelope, Outer}`; consumes generated
`RelayInboundFrame`/`RelayControlFrame`/`PiEnvelopeFrame`/`OuterEnvelope` — no
handwritten mirror. Fail-fast confirmed: invalid JSON + unknown typed frames
rejected at the boundary (`FrameDecodeError::InvalidJson`/`UnknownType`) before
connection dispatch; known malformed control frames rejected by generated serde.
Outer-envelope compatibility preserved: no-top-level-`type` path through
`outer::parse_line()`, opaque `ct`, 4 MiB ceiling, `OuterTooLarge` mapping.
Generated-contract invariant held (extended generator to emit RelayInboundFrame,
regenerated clean + deterministic). The `MalformedPiEnvelope` compat-path
retention (preserves `bad_envelope` transport-error correlation) is sound.
