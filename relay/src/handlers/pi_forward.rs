//! Plan 25 Wave A — Pi-to-Pi envelope forwarding via the relay.
//!
//! Pi-A sends a control frame:
//!
//! ```jsonc
//! { "type": "pi_envelope", "to_pc": "<Pi-B-pubkey-b64>", "to_room": "<room>", "envelope": { ... } }
//! ```
//!
//! The relay authenticates Pi-A via the existing challenge-response (so we
//! already trust `sender_peer_id` here), looks up the `mesh_versions` blob
//! that lists Pi-A and confirms Pi-B is in the same Owner's member list, then
//! forwards to Pi-B's addressed room as:
//!
//! ```jsonc
//! { "type": "pi_envelope_in", "from_pc": "<Pi-A-pubkey>", "to_room": "<room>", "envelope": <verbatim> }
//! ```
//!
//! Cross-PC data-plane forwarding is always room-targeted by relay-owned
//! `(to_pc, to_room)` metadata. Any `session_id` inside `ct`, room metadata, or
//! the generic `AgentEnvelope.body` is endpoint-owned opaque data: this module
//! does not parse it, derive targets from it, log it, or use it as a metric key.
//!
//! Failures don't use a custom error frame — the relay synthesizes an envelope
//! with `body.type = "transport_error"` (per the plan's ACK protocol section),
//! correlated to the sender's original envelope via `re: <original_id>`.

use std::collections::{HashMap, HashSet};
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use axum::extract::ws::Message;
use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use rand::{RngCore, thread_rng};
use tracing::warn;

use crate::mesh::{MeshStore, owner_pk_hash, verify_envelope};
use crate::peers::registry::PeerRegistry;

/// Time-to-live for a positive membership lookup. The plan calls for 60 s.
/// Negative lookups are NOT cached (so adding a Pi to a mesh blob takes
/// effect immediately for subsequent forwards).
const CACHE_TTL: Duration = Duration::from_secs(60);

/// In-memory cache that maps `Pi-pubkey → set of mesh siblings`. Built lazily
/// by scanning the SQLite `mesh_versions` blobs.
#[derive(Debug, Default)]
pub struct MeshAuthCache {
    inner: Mutex<HashMap<String, CachedMembers>>,
}

#[derive(Debug)]
struct CachedMembers {
    members: HashSet<String>,
    cached_at: Instant,
}

impl MeshAuthCache {
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns the set of mesh siblings of `pi_pk` (including `pi_pk` itself),
    /// or `None` if no Owner blob lists this Pi. Refreshes on cache miss /
    /// TTL expiry by scanning all `mesh_versions` blobs.
    fn members_of(&self, pi_pk: &str, store: &MeshStore) -> Option<HashSet<String>> {
        {
            let g = self.inner.lock().unwrap();
            if let Some(c) = g.get(pi_pk)
                && c.cached_at.elapsed() < CACHE_TTL
            {
                return Some(c.members.clone());
            }
        }

        let envelopes = match store.all_envelopes() {
            Ok(records) => records,
            Err(e) => {
                warn!("mesh store read failed during auth: {e}");
                return None;
            }
        };

        for (stored_owner_hash, envelope) in envelopes {
            let header = match verify_envelope(&envelope) {
                Ok(header) => header,
                Err(err) => {
                    warn!(%err, "invalid stored mesh blob skipped during auth");
                    continue;
                }
            };
            let owner_pk_bytes = match B64.decode(&header.owner_pk) {
                Ok(bytes) => bytes,
                Err(err) => {
                    warn!(%err, "stored mesh owner key decode failed during auth");
                    continue;
                }
            };
            if owner_pk_hash(&owner_pk_bytes) != stored_owner_hash.to_lowercase() {
                warn!("stored mesh owner hash mismatch skipped during auth");
                continue;
            }

            let parsed: serde_json::Value = match serde_json::from_slice(&envelope.blob) {
                Ok(v) => v,
                Err(err) => {
                    warn!(%err, "verified mesh blob failed member parse during auth");
                    continue;
                }
            };
            let Some(members_arr) = parsed.get("members").and_then(|v| v.as_array()) else {
                continue;
            };
            let set: HashSet<String> = members_arr
                .iter()
                .filter_map(|m| {
                    m.get("remote_epk")
                        .and_then(|v| v.as_str())
                        .map(String::from)
                })
                .collect();
            if set.contains(pi_pk) {
                let mut g = self.inner.lock().unwrap();
                g.insert(
                    pi_pk.to_string(),
                    CachedMembers {
                        members: set.clone(),
                        cached_at: Instant::now(),
                    },
                );
                return Some(set);
            }
        }
        None
    }

    /// `true` iff both Pis belong to the same Owner's mesh.
    pub fn is_authorized(&self, pi_a: &str, pi_b: &str, store: &MeshStore) -> bool {
        match self.members_of(pi_a, store) {
            Some(members) => members.contains(pi_b),
            None => false,
        }
    }
}

/// What the routing loop should do after calling `handle_pi_envelope`.
pub enum PiForwardResult {
    /// Envelope delivered (or accepted by the channel of) Pi-B.
    Forwarded,
    /// Send this message back to the original sender via their own WS sink.
    /// Always a `pi_envelope_in` whose envelope carries
    /// `body.type = "transport_error"`.
    TransportError(Message),
}

/// Handles one `pi_envelope` frame. `sender_peer_id` is the authenticated
/// Pi-A pubkey (already verified by the WS handshake).
pub async fn handle_pi_envelope(
    sender_peer_id: &str,
    frame: &serde_json::Value,
    registry: &PeerRegistry,
    mesh: &MeshStore,
    cache: &MeshAuthCache,
) -> PiForwardResult {
    let to_pc = frame.get("to_pc").and_then(|v| v.as_str());
    let to_room = frame.get("to_room").and_then(|v| v.as_str());
    let envelope = frame.get("envelope");

    let (to_pc, to_room, envelope) = match (to_pc, to_room, envelope) {
        (Some(pc), Some(room), Some(e)) if !pc.is_empty() && !room.is_empty() && e.is_object() => {
            (pc, room, e)
        }
        _ => {
            return PiForwardResult::TransportError(make_transport_error(
                frame.get("envelope"),
                "bad_envelope",
            ));
        }
    };

    if !cache.is_authorized(sender_peer_id, to_pc, mesh) {
        return PiForwardResult::TransportError(make_transport_error(
            Some(envelope),
            "not_authorized",
        ));
    }

    let outbound = serde_json::json!({
        "type": "pi_envelope_in",
        "from_pc": sender_peer_id,
        "to_room": to_room,
        "envelope": envelope, // verbatim
    });
    let msg = Message::Text(outbound.to_string());

    if registry.forward_to_room(to_pc, to_room, msg) {
        PiForwardResult::Forwarded
    } else {
        PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
    }
}

/// Builds a `pi_envelope_in` frame whose inner envelope carries
/// `body.type = "transport_error"`, correlated to the original via `re`.
fn make_transport_error(envelope: Option<&serde_json::Value>, reason: &str) -> Message {
    let (re, to_addr) = match envelope {
        Some(e) => (
            e.get("id").and_then(|v| v.as_str()).map(String::from),
            e.get("from")
                .and_then(|v| v.as_str())
                .unwrap_or("_unknown")
                .to_string(),
        ),
        None => (None, "_unknown".to_string()),
    };

    let new_id = make_relay_envelope_id();

    let err_envelope = serde_json::json!({
        "from": "_relay",
        "to": to_addr,
        "id": new_id,
        "re": re,
        "body": { "type": "transport_error", "reason": reason },
    });

    let frame = serde_json::json!({
        "type": "pi_envelope_in",
        "from_pc": "_relay",
        "envelope": err_envelope,
    });
    Message::Text(frame.to_string())
}

fn make_relay_envelope_id() -> String {
    let ts_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    let mut bytes = [0u8; 16];
    thread_rng().fill_bytes(&mut bytes);

    bytes[0] = (ts_ms >> 40) as u8;
    bytes[1] = (ts_ms >> 32) as u8;
    bytes[2] = (ts_ms >> 24) as u8;
    bytes[3] = (ts_ms >> 16) as u8;
    bytes[4] = (ts_ms >> 8) as u8;
    bytes[5] = ts_ms as u8;
    bytes[6] = (bytes[6] & 0x0f) | 0x70;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0],
        bytes[1],
        bytes[2],
        bytes[3],
        bytes[4],
        bytes[5],
        bytes[6],
        bytes[7],
        bytes[8],
        bytes[9],
        bytes[10],
        bytes[11],
        bytes[12],
        bytes[13],
        bytes[14],
        bytes[15]
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PresenceManager;
    use crate::RoomManager;
    use ed25519_dalek::{Signer, SigningKey};
    use std::sync::Arc;

    fn fresh_cache_and_store() -> (MeshAuthCache, MeshStore) {
        (MeshAuthCache::new(), MeshStore::open_in_memory().unwrap())
    }

    fn make_owner_key() -> SigningKey {
        SigningKey::generate(&mut rand::thread_rng())
    }

    fn write_owner_blob(store: &MeshStore, owner_sk: &SigningKey, members: &[&str], version: u64) {
        let owner_pk = owner_sk.verifying_key().to_bytes();
        let pk_b64 = B64.encode(owner_pk);
        let members_json: Vec<serde_json::Value> = members
            .iter()
            .map(|m| serde_json::json!({ "remote_epk": m }))
            .collect();
        let blob = serde_json::json!({
            "owner_pk": pk_b64,
            "version": version,
            "members": members_json,
        });
        let blob_bytes = serde_json::to_vec(&blob).unwrap();
        let sig = owner_sk.sign(&blob_bytes).to_bytes();
        store
            .upsert(
                &owner_pk_hash(&owner_pk),
                &owner_pk,
                version,
                &blob_bytes,
                &sig,
                0,
            )
            .unwrap();
    }

    fn write_owner_blob_with_hash(
        store: &MeshStore,
        owner_sk: &SigningKey,
        row_owner_hash: &str,
        members: &[&str],
        version: u64,
    ) {
        let owner_pk = owner_sk.verifying_key().to_bytes();
        let pk_b64 = B64.encode(owner_pk);
        let members_json: Vec<serde_json::Value> = members
            .iter()
            .map(|m| serde_json::json!({ "remote_epk": m }))
            .collect();
        let blob = serde_json::json!({
            "owner_pk": pk_b64,
            "version": version,
            "members": members_json,
        });
        let blob_bytes = serde_json::to_vec(&blob).unwrap();
        let sig = owner_sk.sign(&blob_bytes).to_bytes();
        store
            .upsert(row_owner_hash, &owner_pk, version, &blob_bytes, &sig, 0)
            .unwrap();
    }

    fn write_invalid_owner_blob(
        store: &MeshStore,
        owner_sk: &SigningKey,
        members: &[&str],
        version: u64,
    ) {
        let owner_pk = owner_sk.verifying_key().to_bytes();
        let pk_b64 = B64.encode(owner_pk);
        let members_json: Vec<serde_json::Value> = members
            .iter()
            .map(|m| serde_json::json!({ "remote_epk": m }))
            .collect();
        let blob = serde_json::json!({
            "owner_pk": pk_b64,
            "version": version,
            "members": members_json,
        });
        let blob_bytes = serde_json::to_vec(&blob).unwrap();
        store
            .upsert(
                &owner_pk_hash(&owner_pk),
                &owner_pk,
                version,
                &blob_bytes,
                &[0u8; 64],
                0,
            )
            .unwrap();
    }

    #[tokio::test]
    async fn authorized_same_owner() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        assert!(cache.is_authorized("pi_a", "pi_b", &store));
        assert!(cache.is_authorized("pi_b", "pi_a", &store));
    }

    #[tokio::test]
    async fn not_authorized_cross_owner() {
        let (cache, store) = fresh_cache_and_store();
        let owner_a = make_owner_key();
        let owner_b = make_owner_key();
        write_owner_blob(&store, &owner_a, &["pi_a"], 1);
        write_owner_blob(&store, &owner_b, &["pi_b"], 1);
        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
        assert!(!cache.is_authorized("pi_b", "pi_a", &store));
    }

    #[tokio::test]
    async fn cache_hits_after_first_lookup() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_x", "pi_y"], 1);
        // First lookup: cold (scans store)
        assert!(cache.is_authorized("pi_x", "pi_y", &store));
        // Subsequent lookups: cache HIT (the test merely ensures correctness;
        // the actual cache short-circuit can be observed via tracing or fault
        // injection if needed)
        assert!(cache.is_authorized("pi_x", "pi_y", &store));
        let g = cache.inner.lock().unwrap();
        assert!(g.contains_key("pi_x"), "first lookup must populate cache");
    }

    #[tokio::test]
    async fn invalid_stored_blob_does_not_authorize_members() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_invalid_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);

        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
        let g = cache.inner.lock().unwrap();
        assert!(
            !g.contains_key("pi_a"),
            "invalid mesh blobs must not populate the positive auth cache"
        );
    }

    #[tokio::test]
    async fn stored_owner_hash_mismatch_does_not_authorize_members() {
        let (cache, store) = fresh_cache_and_store();
        let owner = make_owner_key();
        write_owner_blob_with_hash(
            &store,
            &owner,
            "0000000000000000000000000000000000000000000000000000000000000000",
            &["pi_a", "pi_b"],
            1,
        );

        assert!(!cache.is_authorized("pi_a", "pi_b", &store));
    }

    #[tokio::test]
    async fn invalid_stored_blob_returns_not_authorized_for_pi_envelope() {
        let registry = Arc::new(PeerRegistry::new(
            Arc::new(PresenceManager::new()),
            Arc::new(RoomManager::new()),
            Arc::new(crate::metrics::FirehoseMetrics::new()),
        ));
        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        let owner = make_owner_key();
        write_invalid_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);

        let frame = serde_json::json!({
            "type": "pi_envelope",
            "to_pc": "pi_b",
            "to_room": "main",
            "envelope": {
                "from": "a:sess",
                "to": "b:agent",
                "id": "018f4444-4444-7444-8444-444444444444",
                "re": null,
                "body": { "type": "ping" },
            },
        });

        match handle_pi_envelope("pi_a", &frame, &registry, &store, &cache).await {
            PiForwardResult::TransportError(message) => {
                let Message::Text(text) = message else {
                    panic!("transport_error must be a text frame");
                };
                let frame: serde_json::Value = serde_json::from_str(&text).unwrap();
                assert_eq!(frame["envelope"]["body"]["reason"], "not_authorized");
            }
            PiForwardResult::Forwarded => panic!("invalid stored blob must not authorize forward"),
        }
    }

    fn make_registry() -> Arc<PeerRegistry> {
        Arc::new(PeerRegistry::new(
            Arc::new(PresenceManager::new()),
            Arc::new(RoomManager::new()),
            Arc::new(crate::metrics::FirehoseMetrics::new()),
        ))
    }

    fn valid_frame() -> serde_json::Value {
        serde_json::json!({
            "type": "pi_envelope",
            "to_pc": "pi_b",
            "to_room": "main",
            "envelope": {
                "from": "a:sess",
                "to": "b:agent",
                "id": "018f4444-4444-7444-8444-444444444444",
                "re": null,
                "body": { "type": "ping", "session_id": "opaque-session" },
            },
        })
    }

    async fn transport_error_reason(frame: serde_json::Value) -> String {
        let registry = make_registry();
        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        match handle_pi_envelope("pi_a", &frame, &registry, &store, &cache).await {
            PiForwardResult::TransportError(message) => {
                let Message::Text(text) = message else {
                    panic!("transport_error must be a text frame");
                };
                let frame: serde_json::Value = serde_json::from_str(&text).unwrap();
                frame["envelope"]["body"]["reason"]
                    .as_str()
                    .unwrap()
                    .to_string()
            }
            PiForwardResult::Forwarded => panic!("must be transport_error"),
        }
    }

    #[tokio::test]
    async fn bad_envelope_when_missing_to_pc() {
        let mut frame = valid_frame();
        frame.as_object_mut().unwrap().remove("to_pc");
        assert_eq!(transport_error_reason(frame).await, "bad_envelope");
    }

    #[tokio::test]
    async fn bad_envelope_when_missing_to_room() {
        let mut frame = valid_frame();
        frame.as_object_mut().unwrap().remove("to_room");
        assert_eq!(transport_error_reason(frame).await, "bad_envelope");
    }

    #[tokio::test]
    async fn bad_envelope_when_to_room_is_empty() {
        let mut frame = valid_frame();
        frame["to_room"] = serde_json::Value::String(String::new());
        assert_eq!(transport_error_reason(frame).await, "bad_envelope");
    }

    #[tokio::test]
    async fn bad_envelope_when_envelope_is_not_object() {
        let mut frame = valid_frame();
        frame["envelope"] = serde_json::Value::String("not-an-envelope".to_string());
        assert_eq!(transport_error_reason(frame).await, "bad_envelope");
    }

    #[tokio::test]
    async fn valid_room_target_reaches_authorization_without_reading_body_session_id() {
        let frame = valid_frame();
        assert_eq!(transport_error_reason(frame).await, "not_authorized");
    }

    #[tokio::test]
    async fn authorized_forward_targets_only_to_room() {
        let registry = make_registry();
        let (tx_main, mut rx_main) = tokio::sync::mpsc::unbounded_channel::<Message>();
        let (tx_work, mut rx_work) = tokio::sync::mpsc::unbounded_channel::<Message>();
        let _ = registry
            .register(
                "pi_b".to_string(),
                crate::rooms::RoomMeta {
                    room_id: "main".to_string(),
                    name: None,
                    cwd: None,
                    session_id: None,
                    model: None,
                    thinking: None,
                    working: false,
                    started_at: 0,
                },
                tx_main,
            )
            .await;
        let _ = registry
            .register(
                "pi_b".to_string(),
                crate::rooms::RoomMeta {
                    room_id: "work".to_string(),
                    name: None,
                    cwd: None,
                    session_id: None,
                    model: None,
                    thinking: None,
                    working: false,
                    started_at: 0,
                },
                tx_work,
            )
            .await;

        let store = MeshStore::open_in_memory().unwrap();
        let cache = MeshAuthCache::new();
        let owner = make_owner_key();
        write_owner_blob(&store, &owner, &["pi_a", "pi_b"], 1);
        let mut frame = valid_frame();
        frame["to_room"] = serde_json::Value::String("work".to_string());

        match handle_pi_envelope("pi_a", &frame, &registry, &store, &cache).await {
            PiForwardResult::Forwarded => {}
            PiForwardResult::TransportError(_) => panic!("authorized room target should forward"),
        }

        assert!(
            rx_main.try_recv().is_err(),
            "main room must not receive work target"
        );
        let Message::Text(text) = rx_work.try_recv().unwrap() else {
            panic!("forwarded message must be text");
        };
        let forwarded: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(forwarded["type"], "pi_envelope_in");
        assert_eq!(forwarded["to_room"], "work");
        assert_eq!(forwarded["envelope"], frame["envelope"]);
    }
}
