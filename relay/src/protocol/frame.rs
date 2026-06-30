//! Inbound relay WebSocket frame decode boundary.
//!
//! This module is the single place that classifies authenticated inbound text
//! frames as relay control, cross-PC forwarding, or app↔Pi outer envelopes. It
//! consumes generated serde contracts. `serde_json::Value` is limited to the
//! boundary probe and the compatibility `bad_envelope` path for malformed
//! cross-PC frames, whose original envelope fields remain opaque relay data.

pub use crate::protocol::generated::control::RelayControlFrame;
pub use crate::protocol::generated::cross_pc::PiEnvelopeFrame;
use crate::protocol::generated::frame::{RELAY_INBOUND_FRAME_TYPES, RelayInboundFrame};
pub use crate::protocol::generated::outer::OuterEnvelope;
use crate::protocol::outer::{self, parse_line};

#[derive(Debug)]
pub enum DecodedRelayFrame {
    Outer(OuterEnvelope),
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
    /// Compatibility escape hatch for malformed `pi_envelope` frames: the
    /// boundary has classified the frame type, but the existing cross-PC
    /// transport-error path still needs the raw envelope fields to correlate a
    /// `bad_envelope` response.
    MalformedPiEnvelope(serde_json::Value),
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
    let value: serde_json::Value = serde_json::from_str(text)?;
    let Some(frame_type) = value
        .get("type")
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
    else {
        return Ok(DecodedRelayFrame::Outer(parse_line(text)?));
    };

    if !RELAY_INBOUND_FRAME_TYPES.contains(&frame_type.as_str()) {
        return Err(FrameDecodeError::UnknownType(frame_type));
    }

    if frame_type == "pi_envelope" {
        return match serde_json::from_value::<RelayInboundFrame>(value.clone()) {
            Ok(RelayInboundFrame::PiEnvelope(frame)) => Ok(DecodedRelayFrame::PiEnvelope(frame)),
            Ok(RelayInboundFrame::Control(_)) => {
                unreachable!("pi_envelope cannot decode as control")
            }
            Err(_) => Ok(DecodedRelayFrame::MalformedPiEnvelope(value)),
        };
    }

    match serde_json::from_value::<RelayInboundFrame>(value)? {
        RelayInboundFrame::Control(frame) => Ok(DecodedRelayFrame::Control(frame)),
        RelayInboundFrame::PiEnvelope(_) => {
            unreachable!("control frame cannot decode as pi_envelope")
        }
    }
}

impl From<outer::ParseError> for FrameDecodeError {
    fn from(err: outer::ParseError) -> Self {
        match err {
            outer::ParseError::InvalidJson(err) => FrameDecodeError::InvalidJson(err),
            outer::ParseError::TooLarge(estimated, max) => {
                FrameDecodeError::OuterTooLarge { estimated, max }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_json_rejects_before_dispatch() {
        assert!(matches!(
            decode_relay_frame("not json"),
            Err(FrameDecodeError::InvalidJson(_))
        ));
    }

    #[test]
    fn unknown_typed_frame_rejects_before_dispatch() {
        let err = decode_relay_frame(r#"{"type":"mystery_frame","peers":[]}"#)
            .expect_err("unknown typed frame must fail at decode boundary");
        assert!(matches!(
            err,
            FrameDecodeError::UnknownType(t) if t == "mystery_frame"
        ));
    }

    #[test]
    fn no_type_outer_envelope_decodes() {
        let frame = decode_relay_frame(r#"{"peer":"dest","room":"main","ct":"QUJDRA=="}"#)
            .expect("outer envelope without type must decode");
        assert!(matches!(
            frame,
            DecodedRelayFrame::Outer(OuterEnvelope { peer, room, ct })
                if peer == "dest" && room == "main" && ct == "QUJDRA=="
        ));
    }

    #[test]
    fn ct_too_large_rejects_at_boundary() {
        let big = "A".repeat(12 * 1024 * 1024);
        let line = format!(r#"{{"peer":"dest","room":"main","ct":"{}"}}"#, big);
        let err = decode_relay_frame(&line).expect_err("oversized ct must fail");
        assert!(matches!(
            err,
            FrameDecodeError::OuterTooLarge { estimated, max }
                if estimated > max && max == outer::DEFAULT_MAX_CT_MIB * 1024 * 1024
        ));
    }

    #[test]
    fn known_control_frame_decodes_to_generated_variant() {
        let frame = decode_relay_frame(r#"{"type":"subscribe_presence","peers":["pi-a"]}"#)
            .expect("known control frame must decode");
        assert!(matches!(
            frame,
            DecodedRelayFrame::Control(RelayControlFrame::SubscribePresence { peers })
                if peers == vec!["pi-a".to_string()]
        ));
    }
}
