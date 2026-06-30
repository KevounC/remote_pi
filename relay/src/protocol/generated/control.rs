// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: control.

#![allow(dead_code)]

use super::room::RoomMetaPatch;
use serde::{Deserialize, Serialize};

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

#[derive(Debug, Clone, Deserialize)]
pub struct RoomMetaUpdateFrame {
    #[serde(default)]
    pub room_id: Option<String>,
    pub meta: RoomMetaPatch,
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
    RoomMetaUpdate(RoomMetaUpdateFrame),
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
