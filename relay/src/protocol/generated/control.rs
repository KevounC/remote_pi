// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: control.

#![allow(dead_code)]

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RawRelayControlFrame {
    #[serde(rename = "type")]
    pub frame_type: String,
    #[serde(flatten)]
    pub fields: Map<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RelayControlFrame {
    #[serde(rename = "auth")]
    Auth {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "challenge")]
    Challenge {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "hello")]
    Hello {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "outer_envelope")]
    OuterEnvelope {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "peer_offline")]
    PeerOffline {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "peer_online")]
    PeerOnline {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "presence")]
    Presence {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "presence_check")]
    PresenceCheck {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "room_announced")]
    RoomAnnounced {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "room_ended")]
    RoomEnded {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "room_meta_update")]
    RoomMetaUpdate {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "rooms")]
    Rooms {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "rooms_check")]
    RoomsCheck {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "subscribe_presence")]
    SubscribePresence {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "subscribe_rooms")]
    SubscribeRooms {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "unsubscribe_presence")]
    UnsubscribePresence {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
    #[serde(rename = "unsubscribe_rooms")]
    UnsubscribeRooms {
        #[serde(flatten)]
        fields: Map<String, Value>,
    },
}
