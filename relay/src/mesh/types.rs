use serde::Deserialize;

pub use crate::protocol::generated::mesh::{
    MeshEnvelopeWire, MeshGetQuery, MeshGetResponse, MeshPostResponse,
};

/// Decoded envelope after base64-decoding the wire fields.
/// The `blob` bytes are the canonical-JSON payload that was signed;
/// the relay never re-canonicalizes — it only verifies the bytes received.
#[derive(Debug, Clone)]
pub struct MeshEnvelope {
    pub blob: Vec<u8>,
    pub sig: Vec<u8>,
}

/// Header extracted from `blob` JSON. Members and other fields exist in the
/// blob but are NOT inspected by the relay — only `version` and `owner_pk`
/// are needed for verification + storage.
#[derive(Debug, Deserialize)]
pub struct MeshHeader {
    pub version: u64,
    pub owner_pk: String, // base64 STANDARD
}

/// Stored row returned by `MeshStore::get`.
#[derive(Debug, Clone)]
pub struct MeshRecord {
    pub version: u64,
    pub blob: Vec<u8>,
    pub sig: Vec<u8>,
    pub updated_at: i64,
}
