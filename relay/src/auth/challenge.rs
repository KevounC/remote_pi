use crate::protocol::generated::control::{ClientAuthMsg, ServerAuthMsg};
use crate::rooms::RoomMeta;
use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::{Signature, VerifyingKey};
use rand::RngCore as _;

/// Max milliseconds to wait for a "hello" before closing the connection.
pub const HELLO_TIMEOUT_MS: u64 = 5_000;

#[derive(Debug)]
pub struct AuthenticatedPeer {
    pub verifying_key: VerifyingKey,
    pub peer_id: String,
    pub room_meta: RoomMeta,
}

#[derive(Debug, thiserror::Error)]
pub enum AuthError {
    #[error("expected hello, got other message")]
    NoHello,
    #[error("invalid pubkey: {0}")]
    InvalidPubkey(String),
    #[error("base64 decode error: {0}")]
    Base64(#[from] base64::DecodeError),
    #[error("invalid signature")]
    InvalidSig,
    #[error("unexpected message type in auth step")]
    UnexpectedMsg,
    #[error("json parse error: {0}")]
    Json(#[from] serde_json::Error),
}

/// Generates a fresh 32-byte random nonce. Returns (raw bytes, base64 string).
pub fn gen_nonce() -> ([u8; 32], String) {
    let mut nonce = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut nonce);
    let b64 = B64.encode(nonce);
    (nonce, b64)
}

/// Parses a JSONL "hello" line and returns the peer's Ed25519 verifying key.
/// Returns [`AuthError::NoHello`] if the line is not a hello message.
pub fn parse_hello(line: &str) -> Result<VerifyingKey, AuthError> {
    Ok(parse_hello_bootstrap(line, 0)?.verifying_key)
}

pub fn parse_hello_bootstrap(line: &str, now_ms: i64) -> Result<AuthenticatedPeer, AuthError> {
    let msg: ClientAuthMsg = serde_json::from_str(line)?;
    match msg {
        ClientAuthMsg::Hello {
            pubkey,
            room_id,
            room_meta,
        } => {
            let bytes = B64.decode(&pubkey)?;
            let arr: [u8; 32] = bytes
                .try_into()
                .map_err(|_| AuthError::InvalidPubkey("expected 32 bytes".into()))?;
            let verifying_key = VerifyingKey::from_bytes(&arr)
                .map_err(|e| AuthError::InvalidPubkey(e.to_string()))?;
            let peer_id = B64.encode(verifying_key.to_bytes());
            let meta = room_meta.unwrap_or_default();
            Ok(AuthenticatedPeer {
                verifying_key,
                peer_id,
                room_meta: RoomMeta {
                    room_id,
                    name: meta.name,
                    cwd: meta.cwd,
                    model: meta.model,
                    thinking: meta.thinking,
                    working: meta.working,
                    started_at: now_ms,
                },
            })
        }
        _ => Err(AuthError::NoHello),
    }
}

/// Serialises the challenge message to a JSONL string (no trailing newline).
pub fn challenge_line(nonce_b64: &str) -> String {
    serde_json::to_string(&ServerAuthMsg::Challenge {
        nonce: nonce_b64.to_owned(),
    })
    .expect("ServerAuthMsg serialisation is infallible")
}

/// Parses an "auth" line and verifies the Ed25519 signature against `nonce`.
/// Relay never decodes `ct` — this only verifies the auth-handshake signature.
pub fn verify_auth(nonce: &[u8; 32], vk: &VerifyingKey, line: &str) -> Result<(), AuthError> {
    let msg: ClientAuthMsg = serde_json::from_str(line)?;
    let sig_b64 = match msg {
        ClientAuthMsg::Auth { sig } => sig,
        _ => return Err(AuthError::UnexpectedMsg),
    };
    let sig_bytes = B64.decode(&sig_b64)?;
    let sig_arr: [u8; 64] = sig_bytes.try_into().map_err(|_| AuthError::InvalidSig)?;
    let sig = Signature::from_bytes(&sig_arr);
    use ed25519_dalek::Verifier as _;
    vk.verify(nonce, &sig).map_err(|_| AuthError::InvalidSig)
}
