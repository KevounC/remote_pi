// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: control.

#![allow(dead_code)]

use serde::{Deserialize, Deserializer, Serialize};

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientAuthMsg {
    Hello {
        pubkey: String,
        #[serde(default = "default_room")]
        room_id: String,
        #[serde(default)]
        room_meta: Option<HelloRoomMeta>,
    },
    Auth {
        sig: String,
    },
}

#[derive(Debug, Default, Clone, Deserialize)]
pub struct HelloRoomMeta {
    pub name: Option<String>,
    pub cwd: Option<String>,
    pub model: Option<String>,
    pub thinking: Option<String>,
    pub session_id: Option<String>,
    #[serde(default)]
    pub working: bool,
}

fn default_room() -> String {
    "main".to_string()
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerAuthMsg {
    Challenge { nonce: String },
}

#[derive(Debug, Default, Clone, Deserialize)]
pub struct RoomMetaPatch {
    #[serde(default, deserialize_with = "deserialize_nullable_string_patch")]
    pub model: Option<Option<String>>,
    #[serde(default, deserialize_with = "deserialize_nullable_string_patch")]
    pub thinking: Option<Option<String>>,
    #[serde(default, deserialize_with = "deserialize_nullable_string_patch")]
    pub session_id: Option<Option<String>>,
    pub working: Option<bool>,
}

fn deserialize_nullable_string_patch<'de, D>(
    deserializer: D,
) -> Result<Option<Option<String>>, D::Error>
where
    D: Deserializer<'de>,
{
    Option::<String>::deserialize(deserializer).map(Some)
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RelayControlFrame {
    #[serde(rename = "subscribe_presence")]
    SubscribePresence {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "unsubscribe_presence")]
    UnsubscribePresence {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "presence_check")]
    PresenceCheck {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "subscribe_rooms")]
    SubscribeRooms {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "unsubscribe_rooms")]
    UnsubscribeRooms {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "rooms_check")]
    RoomsCheck {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "room_meta_update")]
    RoomMetaUpdate {
        #[serde(default)]
        room_id: Option<String>,
        meta: RoomMetaPatch,
    },
}

pub const RELAY_CONTROL_FRAME_TYPES: &[&str] = &[
    "subscribe_presence",
    "unsubscribe_presence",
    "presence_check",
    "subscribe_rooms",
    "unsubscribe_rooms",
    "rooms_check",
    "room_meta_update",
];

pub fn is_relay_control_frame_type(frame_type: &str) -> bool {
    RELAY_CONTROL_FRAME_TYPES.contains(&frame_type)
}
