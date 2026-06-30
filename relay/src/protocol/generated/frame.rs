// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: frame.

#![allow(dead_code)]

use serde::de;
use serde::{Deserialize, Deserializer};
use serde_json::Value;

use super::control::{RelayControlFrame, is_relay_control_frame_type};
use super::cross_pc::PiEnvelopeFrame;

#[derive(Debug, Clone)]
pub enum RelayInboundFrame {
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
}

pub const RELAY_INBOUND_FRAME_TYPES: &[&str] = &[
    "presence_check",
    "room_meta_update",
    "rooms_check",
    "subscribe_presence",
    "subscribe_rooms",
    "unsubscribe_presence",
    "unsubscribe_rooms",
    "pi_envelope",
];

impl<'de> Deserialize<'de> for RelayInboundFrame {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Value::deserialize(deserializer)?;
        let frame_type = value
            .get("type")
            .and_then(Value::as_str)
            .ok_or_else(|| de::Error::missing_field("type"))?
            .to_string();

        if is_relay_control_frame_type(&frame_type) {
            return serde_json::from_value(value)
                .map(RelayInboundFrame::Control)
                .map_err(de::Error::custom);
        }

        if frame_type == "pi_envelope" {
            return serde_json::from_value(value)
                .map(RelayInboundFrame::PiEnvelope)
                .map_err(de::Error::custom);
        }

        Err(de::Error::unknown_variant(
            &frame_type,
            RELAY_INBOUND_FRAME_TYPES,
        ))
    }
}
