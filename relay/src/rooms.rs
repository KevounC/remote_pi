use std::sync::Arc;

use tokio::sync::Mutex;

use crate::protocol::generated::room;
use crate::subscriptions::SubscriptionIndex;

/// Metadata about one active Pi room (sub-channel of a peer_id).
///
/// Wire fields are generated from `protocol/schema/relay-control.schema.json`.
/// `working` is a compatibility projection cached by the relay. The
/// pi-extension is the only authority for turn lifecycle; the relay stores and
/// forwards the latest projected boolean for room subscribers and `rooms`
/// snapshots. Do not derive turn phase, reply target, or cancel target here.
pub use room::RoomMeta;

/// Patch over the mutable generated `RoomMeta` fields. Each entry distinguishes
/// "field absent in the update" (outer `None`, meaning "leave current") from
/// "field present in the update" (outer `Some(_)`, whose inner `None` means
/// "clear to null" and whose inner `Some(s)` means "set to s").
///
/// Built by the `room_meta_update` handler from the `meta` JSON object; the
/// relay never inspects the inner values beyond JSON-shape (they're forwarded
/// opaquely to subscribers). `working` is non-nullable: absence preserves,
/// `Some(false)` is terminal/idle, and `Some(true)` is active.
pub use room::RoomMetaPatch;

impl RoomMetaPatch {
    /// `true` when at least one field is present (i.e. the patch is a no-op
    /// otherwise). Used by the registry to skip work when callers send empty
    /// `meta: {}`.
    pub fn is_empty(&self) -> bool {
        self.model.is_none() && self.thinking.is_none() && self.working.is_none()
    }
}

#[derive(Debug, Default)]
struct Inner {
    subscriptions: SubscriptionIndex,
}

/// Tracks who has subscribed to room announcements for which peer_ids.
/// Complements PresenceManager: same subscription graph, separate broadcast semantics.
#[derive(Clone, Debug, Default)]
pub struct RoomManager {
    inner: Arc<Mutex<Inner>>,
}

impl RoomManager {
    pub fn new() -> Self {
        Self::default()
    }

    /// Replaces `subscriber`'s full subscription list with `peers`.
    /// Empty list = unsubscribe all.
    pub async fn subscribe(&self, subscriber: String, peers: Vec<String>) {
        let mut g = self.inner.lock().await;
        g.subscriptions.replace(subscriber, peers);
    }

    /// Removes `peers` from `subscriber`'s watched list.
    pub async fn unsubscribe(&self, subscriber: &str, peers: Vec<String>) {
        let mut g = self.inner.lock().await;
        g.subscriptions.remove(subscriber, peers);
    }

    /// Removes all subscriptions for `subscriber` (called on disconnect to prevent leaks).
    pub async fn unsubscribe_all(&self, subscriber: &str) {
        let mut g = self.inner.lock().await;
        g.subscriptions.remove_all(subscriber);
    }

    /// Returns everyone who subscribed to room events for `peer`.
    pub async fn subscribers_of(&self, peer: &str) -> Vec<String> {
        let g = self.inner.lock().await;
        g.subscriptions.subscribers_of(peer)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_room_meta_patch_preserves_absent_null_and_bool_states() {
        let absent: RoomMetaPatch = serde_json::from_value(serde_json::json!({})).unwrap();
        assert!(absent.is_empty());

        let patch: RoomMetaPatch = serde_json::from_value(serde_json::json!({
            "model": null,
            "thinking": "high",
            "working": false,
        }))
        .unwrap();
        assert_eq!(patch.model, Some(None));
        assert_eq!(patch.thinking, Some(Some("high".to_string())));
        assert_eq!(patch.working, Some(false));
        assert!(!patch.is_empty());
    }

    #[test]
    fn generated_room_meta_patch_rejects_nullable_working() {
        let err = serde_json::from_value::<RoomMetaPatch>(serde_json::json!({
            "working": null,
        }))
        .unwrap_err();
        assert!(
            err.to_string().contains("invalid type"),
            "unexpected error: {err}"
        );
    }

    #[tokio::test]
    async fn subscribe_replaces_list() {
        let rm = RoomManager::new();
        rm.subscribe("B".into(), vec!["A".into(), "C".into()]).await;
        assert!(rm.subscribers_of("A").await.contains(&"B".to_string()));

        rm.subscribe("B".into(), vec!["A".into()]).await;
        assert!(!rm.subscribers_of("C").await.contains(&"B".to_string()));
    }

    #[tokio::test]
    async fn subscribe_empty_equals_unsubscribe_all() {
        let rm = RoomManager::new();
        rm.subscribe("B".into(), vec!["A".into()]).await;
        rm.subscribe("B".into(), vec![]).await;
        assert!(rm.subscribers_of("A").await.is_empty());
    }

    #[tokio::test]
    async fn unsubscribe_all_cleans_subscriber_from_sets() {
        let rm = RoomManager::new();
        rm.subscribe("B".into(), vec!["A".into(), "C".into()]).await;
        rm.unsubscribe_all("B").await;
        assert!(rm.subscribers_of("A").await.is_empty());
        assert!(rm.subscribers_of("C").await.is_empty());
    }
}
