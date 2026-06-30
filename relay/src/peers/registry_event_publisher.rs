use std::sync::Arc;

use axum::extract::ws::Message;

use super::connections::ConnectionRegistry;
use super::presence_state::PresenceTransition;
use super::rooms::RoomEnded;
use crate::metrics::FirehoseMetrics;
use crate::presence::PresenceManager;
use crate::rooms::{RoomManager, RoomMeta};

/// Serializes and delivers registry lifecycle events to subscribed peers.
///
/// State modules return transition records; this adapter owns subscriber lookup,
/// relay-event JSON construction, firehose metrics, and delivery over the live
/// connection table. It intentionally preserves the existing unbounded-channel
/// send semantics and does not inspect message contents.
#[derive(Debug)]
pub(crate) struct RegistryEventPublisher {
    delivery: Arc<ConnectionRegistry>,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}

impl RegistryEventPublisher {
    pub(crate) fn new(
        delivery: Arc<ConnectionRegistry>,
        presence: Arc<PresenceManager>,
        rooms: Arc<RoomManager>,
        metrics: Arc<FirehoseMetrics>,
    ) -> Self {
        Self {
            delivery,
            presence,
            rooms,
            metrics,
        }
    }

    pub(crate) async fn publish_room_announced(&self, peer_id: &str, room: &RoomMeta) {
        let room_subs = self.rooms.subscribers_of(peer_id).await;
        if room_subs.is_empty() {
            return;
        }

        let mut announced =
            serde_json::to_value(room).expect("RoomMeta serialization is infallible");
        announced["type"] = "room_announced".into();
        announced["peer"] = peer_id.into();
        self.publish_to_subscribers(&room_subs, announced.to_string());
    }

    pub(crate) async fn publish_room_ended(&self, peer_id: &str, ended: RoomEnded) {
        let room_subs = self.rooms.subscribers_of(peer_id).await;
        if room_subs.is_empty() {
            return;
        }

        let msg = serde_json::json!({
            "type": "room_ended",
            "peer": peer_id,
            "room_id": ended.room_id,
            "since_ts": ended.since_ts,
        })
        .to_string();
        self.publish_to_subscribers(&room_subs, msg);
    }

    pub(crate) async fn publish_presence_transition(&self, transition: PresenceTransition) {
        match transition {
            PresenceTransition::BecameOnline { peer_id } => {
                let pres_subs = self.presence.subscribers_of(&peer_id).await;
                let sub_count = pres_subs.len() as u64;
                if sub_count == 0 {
                    return;
                }

                let msg = serde_json::json!({"type": "peer_online", "peer": peer_id}).to_string();
                self.publish_to_subscribers(&pres_subs, msg);
                self.metrics.inc_peer_online_emitted(sub_count);
            }
            PresenceTransition::StayedOnline { peer_id } => {
                let sub_count = self.presence.subscribers_of(&peer_id).await.len() as u64;
                if sub_count > 0 {
                    self.metrics.inc_peer_online_suppressed(sub_count);
                }
            }
            PresenceTransition::BecameOffline { peer_id, since_ts } => {
                let pres_subs = self.presence.subscribers_of(&peer_id).await;
                if !pres_subs.is_empty() {
                    let msg = serde_json::json!({
                        "type": "peer_offline",
                        "peer": peer_id.as_str(),
                        "since_ts": since_ts,
                    })
                    .to_string();
                    self.publish_to_subscribers(&pres_subs, msg);
                }
                self.presence.record_offline(&peer_id, since_ts).await;
                self.presence.unsubscribe_all(&peer_id).await;
            }
            PresenceTransition::StayedOnlineAfterDisconnect { .. } => {}
        }
    }

    pub(crate) async fn publish_room_meta_updated(
        &self,
        peer_id: &str,
        room_id: &str,
        snapshot: &RoomMeta,
    ) {
        let room_subs = self.rooms.subscribers_of(peer_id).await;
        if room_subs.is_empty() {
            return;
        }

        let mut meta_obj = serde_json::Map::new();
        if let Some(model) = &snapshot.model {
            meta_obj.insert(
                "model".to_string(),
                serde_json::Value::String(model.clone()),
            );
        }
        if let Some(thinking) = &snapshot.thinking {
            meta_obj.insert(
                "thinking".to_string(),
                serde_json::Value::String(thinking.clone()),
            );
        }
        if let Some(session_id) = &snapshot.session_id {
            meta_obj.insert(
                "session_id".to_string(),
                serde_json::Value::String(session_id.clone()),
            );
        }
        // `working` is always present (non-nullable bool), so it always rides
        // along in the broadcast — subscribers can rely on it.
        meta_obj.insert(
            "working".to_string(),
            serde_json::Value::Bool(snapshot.working),
        );
        let msg = serde_json::json!({
            "type": "room_meta_updated",
            "peer": peer_id,
            "room_id": room_id,
            "meta": serde_json::Value::Object(meta_obj),
        })
        .to_string();
        self.publish_to_subscribers(&room_subs, msg);
    }

    pub(crate) fn publish_peer_online_backfill(&self, subscriber: &str, peer_id: &str) {
        let msg = serde_json::json!({"type": "peer_online", "peer": peer_id}).to_string();
        self.send_to_all_rooms_of(subscriber, Message::Text(msg));
    }

    fn publish_to_subscribers(&self, subscribers: &[String], msg: String) {
        for subscriber in subscribers {
            self.send_to_all_rooms_of(subscriber, Message::Text(msg.clone()));
        }
    }

    fn send_to_all_rooms_of(&self, peer_id: &str, msg: Message) {
        let _ = self.delivery.send_to_all_rooms_of(peer_id, msg);
    }
}
