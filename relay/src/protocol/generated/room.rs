// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: room.

#![allow(dead_code)]

use serde::{Deserialize, Serialize};

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct RoomMeta {
    pub model: Option<String>,
    pub thinking: Option<String>,
    #[serde(default)]
    pub working: bool,
}

#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub working: Option<bool>,
}
