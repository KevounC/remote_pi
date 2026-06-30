// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: room.

#![allow(dead_code)]

use serde::{Deserialize, Deserializer, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomMeta {
    pub room_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<String>,
    #[serde(default)]
    pub working: bool,
    pub started_at: i64,
}

#[derive(Debug, Default, Clone, Deserialize)]
pub struct RoomMetaPatch {
    #[serde(default, deserialize_with = "deserialize_nullable_string_patch")]
    pub model: Option<Option<String>>,
    #[serde(default, deserialize_with = "deserialize_nullable_string_patch")]
    pub thinking: Option<Option<String>>,
    #[serde(default, deserialize_with = "deserialize_non_null_bool_patch")]
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

fn deserialize_non_null_bool_patch<'de, D>(deserializer: D) -> Result<Option<bool>, D::Error>
where
    D: Deserializer<'de>,
{
    bool::deserialize(deserializer).map(Some)
}
