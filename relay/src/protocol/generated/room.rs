// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: room.

#![allow(dead_code)]

use serde::de::{self, MapAccess, Visitor};
use serde::{Deserialize, Deserializer, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomMeta {
    pub room_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub thinking: Option<String>,
    #[serde(default)]
    pub working: bool,
    pub started_at: i64,
}

#[derive(Debug, Default, Clone)]
pub struct RoomMetaPatch {
    pub model: Option<Option<String>>,
    pub thinking: Option<Option<String>>,
    pub session_id: Option<Option<String>>,
    pub working: Option<bool>,
}

const ROOM_META_PATCH_FIELDS: &[&str] = &["model", "thinking", "session_id", "working"];

impl<'de> Deserialize<'de> for RoomMetaPatch {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_map(RoomMetaPatchVisitor)
    }
}

struct RoomMetaPatchVisitor;

impl<'de> Visitor<'de> for RoomMetaPatchVisitor {
    type Value = RoomMetaPatch;

    fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
        formatter.write_str("a room metadata patch object")
    }

    fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
    where
        A: MapAccess<'de>,
    {
        let mut patch = RoomMetaPatch::default();
        while let Some(key) = map.next_key::<String>()? {
            match key.as_str() {
                "model" => {
                    if patch.model.is_some() {
                        return Err(de::Error::duplicate_field("model"));
                    }
                    patch.model = Some(map.next_value::<Option<String>>()?);
                }
                "thinking" => {
                    if patch.thinking.is_some() {
                        return Err(de::Error::duplicate_field("thinking"));
                    }
                    patch.thinking = Some(map.next_value::<Option<String>>()?);
                }
                "session_id" => {
                    if patch.session_id.is_some() {
                        return Err(de::Error::duplicate_field("session_id"));
                    }
                    patch.session_id = Some(map.next_value::<Option<String>>()?);
                }
                "working" => {
                    if patch.working.is_some() {
                        return Err(de::Error::duplicate_field("working"));
                    }
                    patch.working = Some(map.next_value::<bool>()?);
                }
                other => return Err(de::Error::unknown_field(other, ROOM_META_PATCH_FIELDS)),
            }
        }
        Ok(patch)
    }
}
