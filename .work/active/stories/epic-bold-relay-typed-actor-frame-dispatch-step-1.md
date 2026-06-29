---
id: epic-bold-relay-typed-actor-frame-dispatch-step-1
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-frame-dispatch
depends_on: [epic-bold-generated-protocol-rust-codegen]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
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

## Rollback

Revert `relay/src/protocol/frame.rs` and return the routing loop to its current inline parse path. Generated protocol artifacts can remain because this story only consumes them.
