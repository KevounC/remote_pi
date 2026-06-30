use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::ws::Message;
use tokio::sync::mpsc;

use super::connections::ConnectionRegistry;
use super::rooms::RoomStateStore;
use crate::metrics::FirehoseMetrics;
use crate::presence::PresenceManager;
use crate::rooms::{RoomManager, RoomMeta, RoomMetaPatch};

/// Maps `(peer_id, room_id)` pairs to a *list* of live connections.
///
/// Plan 23 (Wave 2C) relaxed the "one connection per (peer, room)" invariant:
/// the registry now accepts N simultaneous connections at the same key —
/// representing N devices of the same human Owner (shared Ed25519 key
/// sincronizada via iCloud Keychain / Block Store). Each device authenticates
/// independently via challenge-response, so admission is still controlled by
/// possession of the private key.
///
/// Data-plane forwarding is keyed by explicit `(owner_pk, room_id)` targets;
/// the registry never derives a route from endpoint-owned session metadata.
/// Every live conn in the corresponding `Vec` receives a copy. The originating
/// connection skips itself via `from_conn_id`, so a multi-device app sees
/// outgoing messages only on the device that sent them.
///
/// Lifecycle events:
/// - `room_announced` fires once, when the *first* conn opens a room.
/// - `room_ended` fires once, when the *last* conn at a room disconnects.
/// - `peer_online` fires only on a real **offline → online** transition: when
///   the peer had **zero** live conns immediately before this register. A
///   second/third conn from the same peer is silently absorbed (no extra
///   `peer_online` for subscribers). The historic "ALWAYS fires" defense
///   against zombie conns was retired here because (a) clients now dedupe
///   client-side anyway and (b) it was generating a firehose of identical
///   frames whenever multiple Owner devices reconnected.
///
///   Zombie reasoning: if a phantom conn is still in the map, `was_offline ==
///   false` and we skip the emit — subscribers already think the peer is
///   online (which is still effectively true at the public protocol level).
///   When the zombie is finally cleaned, `unregister` only fires
///   `peer_offline` if the **whole** peer is gone — never wrongly while a
///   real conn is alive.
/// - `peer_offline` fires only when the peer transitions from N → 0 total
///   connections (asymmetric still: online and offline both gated by real
///   state changes, but the offline edge is the authoritative one).
#[derive(Debug)]
pub struct PeerRegistry {
    connections: ConnectionRegistry,
    room_state: RoomStateStore,
    presence: Arc<PresenceManager>,
    rooms: Arc<RoomManager>,
    metrics: Arc<FirehoseMetrics>,
}

impl PeerRegistry {
    pub fn new(
        presence: Arc<PresenceManager>,
        rooms: Arc<RoomManager>,
        metrics: Arc<FirehoseMetrics>,
    ) -> Self {
        Self {
            connections: ConnectionRegistry::new(),
            room_state: RoomStateStore::new(),
            presence,
            rooms,
            metrics,
        }
    }

    /// Registers a new connection at `(peer_id, room_meta.room_id)`.
    ///
    /// Multiple connections may coexist at the same key — each gets a unique
    /// `conn_id`. `room_announced` fires only on the **first** conn at the
    /// room (to avoid spamming metadata churn). `peer_online` fires only
    /// when `was_offline_before == true` — i.e. on a real offline→online
    /// transition, not on every register. See struct-level docs.
    pub async fn register(
        &self,
        peer_id: String,
        room_meta: RoomMeta,
        tx: mpsc::UnboundedSender<Message>,
    ) -> u64 {
        let room_id = room_meta.room_id.clone();
        let insert = self.connections.insert(&peer_id, &room_id, tx);
        let announced_meta = self
            .room_state
            .on_connection_inserted(&peer_id, room_meta, &insert);

        // room_announced fires once per (peer, room) lifecycle. Duplicate
        // connections refresh the canonical rooms snapshot but do not announce.
        if let Some(announced_meta) = announced_meta {
            let room_subs = self.rooms.subscribers_of(&peer_id).await;
            if !room_subs.is_empty() {
                let mut announced = serde_json::to_value(&announced_meta)
                    .expect("RoomMeta serialization is infallible");
                announced["type"] = "room_announced".into();
                announced["peer"] = peer_id.as_str().into();
                let msg = announced.to_string();
                for sub in &room_subs {
                    self.forward_to_all_rooms_of(sub, Message::Text(msg.clone()));
                }
            }
        }

        // peer_online fires only on a real offline → online transition.
        // Re-registers from a peer that already had a live conn produce no
        // new push to subscribers — they already think it's online.
        let pres_subs = self.presence.subscribers_of(&peer_id).await;
        let sub_count = pres_subs.len() as u64;
        if sub_count > 0 {
            if insert.was_offline_before {
                let msg = serde_json::json!({"type": "peer_online", "peer": peer_id}).to_string();
                for sub in pres_subs {
                    self.forward_to_all_rooms_of(&sub, Message::Text(msg.clone()));
                }
                self.metrics.inc_peer_online_emitted(sub_count);
            } else {
                self.metrics.inc_peer_online_suppressed(sub_count);
            }
        }

        insert.conn_id
    }

    /// Immediately pushes a `peer_online` to `subscriber` for every peer in
    /// `peers` that is currently online. Called by the handler right after
    /// `subscribe_presence` to bridge the gap when a peer subscribed *after*
    /// its target was already connected.
    pub fn backfill_presence(&self, subscriber: &str, peers: &[String]) {
        for peer in peers {
            if self.is_online(peer) {
                let msg = serde_json::json!({"type": "peer_online", "peer": peer}).to_string();
                self.forward_to_all_rooms_of(subscriber, Message::Text(msg));
            }
        }
    }

    /// Removes the connection identified by `conn_id` from the `Vec` at
    /// `(peer_id, room_id)`. When the `Vec` empties, the entry is removed and
    /// `room_ended` is broadcast; when the peer has no remaining rooms,
    /// `peer_offline` is also broadcast.
    ///
    /// Stale `conn_id`s (already removed, or never registered there) are no-ops.
    pub async fn unregister(&self, peer_id: &str, room_id: &str, conn_id: u64) {
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;

        let remove = self.connections.remove(peer_id, room_id, conn_id);
        let ended = self
            .room_state
            .on_connection_removed(peer_id, room_id, &remove);

        if let Some(ended) = ended {
            let room_subs = self.rooms.subscribers_of(peer_id).await;
            if !room_subs.is_empty() {
                let msg = serde_json::json!({
                    "type": "room_ended",
                    "peer": peer_id,
                    "room_id": ended.room_id,
                    "since_ts": now_ms,
                })
                .to_string();
                for sub in &room_subs {
                    self.forward_to_all_rooms_of(sub, Message::Text(msg.clone()));
                }
            }
        }

        if remove.peer_offlined {
            let pres_subs = self.presence.subscribers_of(peer_id).await;
            if !pres_subs.is_empty() {
                let msg = serde_json::json!({
                    "type": "peer_offline",
                    "peer": peer_id,
                    "since_ts": now_ms,
                })
                .to_string();
                for sub in pres_subs {
                    self.forward_to_all_rooms_of(&sub, Message::Text(msg.clone()));
                }
            }
            self.presence.record_offline(peer_id, now_ms).await;
            self.presence.unsubscribe_all(peer_id).await;
        }
    }

    /// Returns `true` if `peer_id` has at least one live connection.
    pub fn is_online(&self, peer_id: &str) -> bool {
        self.connections.is_online(peer_id)
    }

    /// Returns one `RoomMeta` per distinct live room of `peer_id`.
    ///
    /// This is the authoritative `rooms` snapshot for currently live rooms.
    /// The `working` value inside each entry is only the latest compatibility
    /// projection published by the pi-extension; the relay does not infer or
    /// synthesize turn lifecycle from it.
    ///
    /// Multiple conns at the same room collapse to a single canonical entry;
    /// later duplicate registrations refresh that snapshot for compatibility.
    pub fn rooms_of(&self, peer_id: &str) -> Vec<RoomMeta> {
        self.room_state.rooms_of(peer_id)
    }

    /// Broadcasts `msg` to every live connection at `(dest_peer, dest_room)`
    /// **except** the one whose conn_id equals `from_conn_id` (skip-sender).
    ///
    /// Returns `true` if at least one recipient received the message.
    /// Pass any `from_conn_id` that is not part of the destination `Vec`
    /// (e.g. the sender's own conn_id from another room) to deliver to all.
    /// Never inspects message content.
    pub fn forward(
        &self,
        dest_peer: &str,
        dest_room: &str,
        msg: Message,
        from_conn_id: u64,
    ) -> bool {
        self.connections
            .send_to_room(dest_peer, dest_room, msg, from_conn_id)
    }

    /// Applies `patch` to the canonical room state at `(peer_id, room_id)` and
    /// broadcasts `room_meta_updated` to room subscribers. Returns `false`
    /// when no entries exist for the pair (so the handler can log and drop).
    ///
    /// Patch semantics: only fields explicitly present in `patch` are written
    /// (see [`RoomMetaPatch`]). The broadcast carries the **post-patch**
    /// full state of the mutable fields — subscribers replace their cached
    /// `meta` wholesale instead of merging field-by-field. Nullable fields
    /// that are still `None` after the patch are omitted from `meta` (matching
    /// the `skip_serializing_if` convention used for `RoomMeta` itself); the
    /// non-nullable `working` projection bool is always present in the broadcast.
    ///
    /// An empty patch (no fields present) still returns `true` if the
    /// `(peer, room)` pair exists, but skips the broadcast — nothing changed.
    pub async fn update_room_meta(
        &self,
        peer_id: &str,
        room_id: &str,
        patch: RoomMetaPatch,
    ) -> bool {
        let is_empty_patch = patch.is_empty();
        let patch_result = match self.room_state.apply_patch(peer_id, room_id, patch) {
            Some(result) => result,
            None => return false,
        };

        // Empty patch → state didn't change, suppress broadcast.
        if is_empty_patch {
            return true;
        }

        let room_subs = self.rooms.subscribers_of(peer_id).await;
        if !room_subs.is_empty() {
            let snapshot = patch_result.meta;
            let mut meta_obj = serde_json::Map::new();
            if let Some(m) = &snapshot.model {
                meta_obj.insert("model".to_string(), serde_json::Value::String(m.clone()));
            }
            if let Some(t) = &snapshot.thinking {
                meta_obj.insert("thinking".to_string(), serde_json::Value::String(t.clone()));
            }
            if let Some(session_id) = &snapshot.session_id {
                meta_obj.insert(
                    "session_id".to_string(),
                    serde_json::Value::String(session_id.clone()),
                );
            }
            // `working` is always present (non-nullable bool), so it always
            // rides along in the broadcast — subscribers can rely on it.
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
            for sub in &room_subs {
                self.forward_to_all_rooms_of(sub, Message::Text(msg.clone()));
            }
        }

        true
    }

    /// Sends `msg` to every live connection of `peer_id` across all rooms.
    /// Used for control-frame pushes (`peer_online`/`peer_offline`,
    /// `room_announced`/`room_ended`, `room_meta_updated`) where the
    /// subscriber's room isn't known in advance.
    fn forward_to_all_rooms_of(&self, peer_id: &str, msg: Message) {
        let _ = self.connections.send_to_all_rooms_of(peer_id, msg);
    }

    /// Sends `msg` to every live connection of `peer_id` across all rooms.
    /// Returns true when at least one live connection was present. Cross-PC
    /// data-plane forwarding uses this peer-wide behavior until canonical
    /// session/room targeting lands as a separate protocol change.
    pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool {
        self.connections.send_to_peer(peer_id, msg)
    }

    /// Sends `msg` to every live connection at one explicit `(peer, room)`.
    /// Reserved for protocol paths that explicitly carry a relay-owned room
    /// target; cross-PC forwarding stays peer-wide until that target is added.
    pub fn forward_to_room(&self, peer_id: &str, room_id: &str, msg: Message) -> bool {
        const EXTERNAL_CONN_ID: u64 = u64::MAX;
        self.forward(peer_id, room_id, msg, EXTERNAL_CONN_ID)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::presence::PresenceManager;
    use crate::rooms::{RoomManager, RoomMeta};

    fn make_meta(room_id: &str) -> RoomMeta {
        RoomMeta {
            room_id: room_id.into(),
            name: None,
            cwd: None,
            session_id: None,
            model: None,
            thinking: None,
            working: false,
            started_at: 0,
        }
    }

    fn make_registry() -> PeerRegistry {
        let presence = Arc::new(PresenceManager::new());
        let rooms = Arc::new(RoomManager::new());
        let metrics = Arc::new(FirehoseMetrics::new());
        PeerRegistry::new(presence, rooms, metrics)
    }

    /// Sentinel `from_conn_id` for "no real sender to skip" — guaranteed not
    /// to collide with any conn_id allocated by the registry in tests.
    const EXTERNAL: u64 = u64::MAX;

    #[tokio::test]
    async fn two_rooms_same_peer_both_accepted() {
        let reg = make_registry();
        let peer = "peer_a".to_string();

        let (tx_main, mut rx_main) = mpsc::unbounded_channel::<Message>();
        let (tx_work, mut rx_work) = mpsc::unbounded_channel::<Message>();

        let conn_main = reg.register(peer.clone(), make_meta("main"), tx_main).await;
        let conn_work = reg.register(peer.clone(), make_meta("work"), tx_work).await;

        assert_ne!(conn_main, conn_work);

        assert!(reg.forward(&peer, "main", Message::Text("to_main".into()), EXTERNAL));
        assert_eq!(rx_main.try_recv().unwrap().to_text().unwrap(), "to_main");

        assert!(reg.forward(&peer, "work", Message::Text("to_work".into()), EXTERNAL));
        assert_eq!(rx_work.try_recv().unwrap().to_text().unwrap(), "to_work");

        reg.unregister(&peer, "work", conn_work).await;
        assert!(!reg.forward(&peer, "work", Message::Text("gone".into()), EXTERNAL));
        assert!(reg.forward(&peer, "main", Message::Text("still_there".into()), EXTERNAL));
        let _ = rx_main.try_recv();
    }

    #[tokio::test]
    async fn forward_to_room_targets_one_room_not_every_room_for_peer() {
        let reg = make_registry();
        let peer = "peer_a".to_string();

        let (tx_main, mut rx_main) = mpsc::unbounded_channel::<Message>();
        let (tx_work, mut rx_work) = mpsc::unbounded_channel::<Message>();

        let _ = reg.register(peer.clone(), make_meta("main"), tx_main).await;
        let _ = reg.register(peer.clone(), make_meta("work"), tx_work).await;

        assert!(reg.forward_to_room(&peer, "work", Message::Text("to_work".into())));
        assert!(
            rx_main.try_recv().is_err(),
            "main room must not receive work target"
        );
        assert_eq!(rx_work.try_recv().unwrap().to_text().unwrap(), "to_work");
    }

    /// Two conns at the same (peer, room) now coexist. `forward` with the first
    /// conn's id as `from_conn_id` delivers only to the second (skip-sender).
    #[tokio::test]
    async fn duplicate_room_accepted_and_broadcast() {
        let reg = make_registry();
        let peer = "peer_a".to_string();

        let (tx1, mut rx1) = mpsc::unbounded_channel::<Message>();
        let (tx2, mut rx2) = mpsc::unbounded_channel::<Message>();

        let conn1 = reg.register(peer.clone(), make_meta("main"), tx1).await;
        let conn2 = reg.register(peer.clone(), make_meta("main"), tx2).await;
        assert_ne!(conn1, conn2);

        // Send "from" conn1 → only conn2 receives.
        assert!(reg.forward(&peer, "main", Message::Text("hi".into()), conn1));
        assert!(rx1.try_recv().is_err(), "sender must not echo");
        assert_eq!(rx2.try_recv().unwrap().to_text().unwrap(), "hi");

        // Send "from" conn2 → only conn1 receives.
        assert!(reg.forward(&peer, "main", Message::Text("hi2".into()), conn2));
        assert_eq!(rx1.try_recv().unwrap().to_text().unwrap(), "hi2");
        assert!(rx2.try_recv().is_err());
    }

    /// Duplicate connections refresh the canonical `rooms_of` snapshot using
    /// the most recently registered metadata (the old `Vec::last()` behavior)
    /// but only the first connection emits `room_announced`; `room_ended` waits
    /// until the last duplicate disconnects.
    #[tokio::test]
    async fn duplicate_connection_refreshes_room_snapshot_without_duplicate_events() {
        let presence = Arc::new(PresenceManager::new());
        let rooms = Arc::new(RoomManager::new());
        let metrics = Arc::new(FirehoseMetrics::new());
        let reg = PeerRegistry::new(presence, rooms.clone(), metrics);

        let pi = "pi".to_string();
        let app = "app".to_string();

        let (tx_app, mut rx_app) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(app.clone(), make_meta("main"), tx_app).await;
        rooms.subscribe(app.clone(), vec![pi.clone()]).await;

        let mut first_meta = make_meta("main");
        first_meta.model = Some("old-model".to_string());
        first_meta.working = false;
        let (tx_pi_1, _rx_pi_1) = mpsc::unbounded_channel::<Message>();
        let conn1 = reg.register(pi.clone(), first_meta, tx_pi_1).await;

        let announced = rx_app
            .try_recv()
            .expect("first connection emits room_announced");
        let announced: serde_json::Value =
            serde_json::from_str(announced.to_text().unwrap()).unwrap();
        assert_eq!(announced["type"], "room_announced");
        assert_eq!(announced["model"], "old-model");
        assert_eq!(announced["working"], false);

        let mut refreshed_meta = make_meta("main");
        refreshed_meta.model = Some("new-model".to_string());
        refreshed_meta.session_id = Some("sess-2".to_string());
        refreshed_meta.working = true;
        let (tx_pi_2, _rx_pi_2) = mpsc::unbounded_channel::<Message>();
        let conn2 = reg.register(pi.clone(), refreshed_meta, tx_pi_2).await;

        assert!(
            rx_app.try_recv().is_err(),
            "duplicate room connection must not emit a second room_announced"
        );
        let snapshot = reg.rooms_of(&pi);
        assert_eq!(snapshot.len(), 1);
        assert_eq!(snapshot[0].model.as_deref(), Some("new-model"));
        assert_eq!(snapshot[0].session_id.as_deref(), Some("sess-2"));
        assert!(snapshot[0].working);

        reg.unregister(&pi, "main", conn1).await;
        assert!(
            rx_app.try_recv().is_err(),
            "removing a non-last duplicate must not emit room_ended"
        );
        assert_eq!(reg.rooms_of(&pi).len(), 1);

        reg.unregister(&pi, "main", conn2).await;
        let ended = rx_app
            .try_recv()
            .expect("last duplicate disconnect emits room_ended");
        let ended: serde_json::Value = serde_json::from_str(ended.to_text().unwrap()).unwrap();
        assert_eq!(ended["type"], "room_ended");
        assert_eq!(ended["room_id"], "main");
        assert!(reg.rooms_of(&pi).is_empty());
    }

    /// Three conns at same (peer, room); one disconnects; remaining two keep
    /// receiving broadcasts from external senders.
    #[tokio::test]
    async fn three_conns_one_disconnects_broadcast_continues() {
        let reg = make_registry();
        let peer = "peer_a".to_string();

        let (tx1, mut rx1) = mpsc::unbounded_channel::<Message>();
        let (tx2, mut rx2) = mpsc::unbounded_channel::<Message>();
        let (tx3, mut rx3) = mpsc::unbounded_channel::<Message>();

        let _conn1 = reg.register(peer.clone(), make_meta("main"), tx1).await;
        let conn2 = reg.register(peer.clone(), make_meta("main"), tx2).await;
        let _conn3 = reg.register(peer.clone(), make_meta("main"), tx3).await;

        reg.unregister(&peer, "main", conn2).await;

        assert!(reg.forward(&peer, "main", Message::Text("ping".into()), EXTERNAL));
        assert_eq!(rx1.try_recv().unwrap().to_text().unwrap(), "ping");
        assert!(
            rx2.try_recv().is_err(),
            "disconnected conn must not receive"
        );
        assert_eq!(rx3.try_recv().unwrap().to_text().unwrap(), "ping");
    }

    /// `from_conn_id` outside the destination Vec → all conns at that pair
    /// receive. Models the common "another peer sends to (owner_pk, main)" case.
    #[tokio::test]
    async fn forward_with_unknown_from_conn_id_reaches_all() {
        let reg = make_registry();
        let peer = "peer_a".to_string();

        let (tx1, mut rx1) = mpsc::unbounded_channel::<Message>();
        let (tx2, mut rx2) = mpsc::unbounded_channel::<Message>();

        let _ = reg.register(peer.clone(), make_meta("main"), tx1).await;
        let _ = reg.register(peer.clone(), make_meta("main"), tx2).await;

        assert!(reg.forward(&peer, "main", Message::Text("from_pi".into()), EXTERNAL));
        assert_eq!(rx1.try_recv().unwrap().to_text().unwrap(), "from_pi");
        assert_eq!(rx2.try_recv().unwrap().to_text().unwrap(), "from_pi");
    }

    /// Single-conn case: skip-sender with own id → nobody receives.
    /// External sender → that single conn receives.
    #[tokio::test]
    async fn single_conn_skip_sender() {
        let reg = make_registry();
        let peer = "peer_a".to_string();

        let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
        let conn = reg.register(peer.clone(), make_meta("main"), tx).await;

        assert!(!reg.forward(&peer, "main", Message::Text("echo".into()), conn));
        assert!(rx.try_recv().is_err());

        assert!(reg.forward(&peer, "main", Message::Text("hi".into()), EXTERNAL));
        assert_eq!(rx.try_recv().unwrap().to_text().unwrap(), "hi");
    }

    /// Re-calling `unregister` with a stale `conn_id` does not affect any
    /// other live conn at the same key.
    #[tokio::test]
    async fn stale_unregister_is_noop() {
        let reg = make_registry();
        let peer = "peer_a".to_string();

        let (tx_a, _) = mpsc::unbounded_channel::<Message>();
        let (tx_b, mut rx_b) = mpsc::unbounded_channel::<Message>();

        let conn_a = reg.register(peer.clone(), make_meta("main"), tx_a).await;
        reg.unregister(&peer, "main", conn_a).await;
        let conn_b = reg.register(peer.clone(), make_meta("main"), tx_b).await;

        // Stale unregister of conn_a is a no-op.
        reg.unregister(&peer, "main", conn_a).await;
        assert!(reg.forward(&peer, "main", Message::Text("alive".into()), EXTERNAL));
        assert_eq!(rx_b.try_recv().unwrap().to_text().unwrap(), "alive");

        // Correct unregister removes the last conn → entry gone.
        reg.unregister(&peer, "main", conn_b).await;
        assert!(!reg.forward(&peer, "main", Message::Text("gone".into()), EXTERNAL));
    }

    /// First register from an offline peer with a presence subscriber must
    /// emit one `peer_online`; a second register from the **same** peer (no
    /// real transition) must NOT emit again and must bump the suppressed
    /// counter instead.
    #[tokio::test]
    async fn peer_online_fires_only_on_real_transition() {
        let presence = Arc::new(PresenceManager::new());
        let rooms = Arc::new(RoomManager::new());
        let metrics = Arc::new(FirehoseMetrics::new());
        let reg = PeerRegistry::new(presence.clone(), rooms, metrics.clone());

        let pi = "pi".to_string();
        let app = "app".to_string();

        // App is online and subscribes to Pi's presence.
        let (tx_app, mut rx_app) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(app.clone(), make_meta("main"), tx_app).await;
        presence.subscribe(app.clone(), vec![pi.clone()]).await;

        // First Pi conn → real offline→online → app receives peer_online.
        let (tx_pi_1, _) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(pi.clone(), make_meta("main"), tx_pi_1).await;
        let m1 = rx_app.try_recv().unwrap();
        let v1: serde_json::Value = serde_json::from_str(m1.to_text().unwrap()).unwrap();
        assert_eq!(v1["type"], "peer_online");
        assert_eq!(v1["peer"], pi.clone());

        // Second conn from the same Pi (no transition) → no extra peer_online.
        let (tx_pi_2, _) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(pi.clone(), make_meta("work"), tx_pi_2).await;
        assert!(
            rx_app.try_recv().is_err(),
            "second register at already-online peer must NOT emit peer_online"
        );

        // Metrics: 1 emitted, 1 suppressed (each over 1 subscriber).
        let [emitted, suppressed, ..] = metrics.snapshot();
        assert_eq!(emitted, 1, "snapshot: {:?}", metrics.snapshot());
        assert_eq!(suppressed, 1, "snapshot: {:?}", metrics.snapshot());
    }

    /// Helper: a Pi with one `main` room plus an `app` subscribed to that
    /// peer's room events. Returns the registry, the shared `rooms` handle,
    /// the peer ids, and the app's receiver (drained of any backfill).
    async fn meta_fixture() -> (PeerRegistry, String, mpsc::UnboundedReceiver<Message>) {
        let presence = Arc::new(PresenceManager::new());
        let rooms = Arc::new(RoomManager::new());
        let metrics = Arc::new(FirehoseMetrics::new());
        let reg = PeerRegistry::new(presence, rooms.clone(), metrics);

        let pi = "pi".to_string();
        let app = "app".to_string();

        // Pi registers first, *before* the app subscribes — so the app gets no
        // `room_announced` backfill and its channel only carries the
        // `room_meta_updated` pushes the tests assert on.
        let (tx_pi, _rx_pi) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(pi.clone(), make_meta("main"), tx_pi).await;

        let (tx_app, rx_app) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(app.clone(), make_meta("main"), tx_app).await;
        rooms.subscribe(app.clone(), vec![pi.clone()]).await;

        (reg, pi, rx_app)
    }

    fn recv_meta(rx: &mut mpsc::UnboundedReceiver<Message>) -> serde_json::Value {
        let msg = rx
            .try_recv()
            .expect("subscriber must receive room_meta_updated");
        let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
        assert_eq!(v["type"], "room_meta_updated");
        v
    }

    /// `working: true` patch broadcasts the post-patch state to subscribers.
    #[tokio::test]
    async fn working_true_patch_broadcasts_true() {
        let (reg, pi, mut rx_app) = meta_fixture().await;

        let patch = RoomMetaPatch {
            working: Some(true),
            ..Default::default()
        };
        assert!(reg.update_room_meta(&pi, "main", patch).await);

        let v = recv_meta(&mut rx_app);
        assert_eq!(v["peer"], pi);
        assert_eq!(v["room_id"], "main");
        assert_eq!(v["meta"]["working"], true);
    }

    /// `working: false` patch is a real (non-empty) patch and broadcasts
    /// `working: false` — flipping a previously-true room back off.
    #[tokio::test]
    async fn working_false_patch_broadcasts_false() {
        let (reg, pi, mut rx_app) = meta_fixture().await;

        // Turn it on, then off.
        let _ = reg
            .update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    working: Some(true),
                    ..Default::default()
                },
            )
            .await;
        let _ = recv_meta(&mut rx_app); // drain the `true` broadcast

        assert!(
            reg.update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    working: Some(false),
                    ..Default::default()
                },
            )
            .await
        );

        let v = recv_meta(&mut rx_app);
        assert_eq!(v["meta"]["working"], false);
    }

    /// A patch that omits `working` (e.g. a model-only update) must NOT zero a
    /// previously-set `working: true` — merge-patch absence leaves it intact,
    /// and the broadcast re-carries the preserved value.
    #[tokio::test]
    async fn working_absent_patch_does_not_zero() {
        let (reg, pi, mut rx_app) = meta_fixture().await;

        let _ = reg
            .update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    working: Some(true),
                    ..Default::default()
                },
            )
            .await;
        let _ = recv_meta(&mut rx_app); // drain the `true` broadcast

        // Model-only patch: `working` is absent → must be left untouched.
        assert!(
            reg.update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    model: Some(Some("opus".into())),
                    ..Default::default()
                },
            )
            .await
        );

        let v = recv_meta(&mut rx_app);
        assert_eq!(v["meta"]["model"], "opus");
        assert_eq!(
            v["meta"]["working"], true,
            "absent `working` in a patch must not clear it"
        );
    }

    /// Nullable string patch fields use merge-patch semantics: a string sets
    /// the value, and explicit `null` clears it without treating the value as a
    /// route key or loggable dimension.
    #[tokio::test]
    async fn nullable_string_patch_clears_session_id_metadata() {
        let (reg, pi, mut rx_app) = meta_fixture().await;

        assert!(
            reg.update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    session_id: Some(Some("sess-1".into())),
                    ..Default::default()
                },
            )
            .await
        );
        let v = recv_meta(&mut rx_app);
        assert_eq!(v["meta"]["session_id"], "sess-1");
        assert_eq!(reg.rooms_of(&pi)[0].session_id.as_deref(), Some("sess-1"));

        assert!(
            reg.update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    session_id: Some(None),
                    ..Default::default()
                },
            )
            .await
        );
        let v = recv_meta(&mut rx_app);
        let meta = v["meta"].as_object().expect("meta object");
        assert!(!meta.contains_key("session_id"));
        assert!(reg.rooms_of(&pi)[0].session_id.is_none());
    }

    /// Empty patches still acknowledge existing rooms but do not broadcast a
    /// no-op update.
    #[tokio::test]
    async fn empty_patch_is_acknowledged_without_broadcast() {
        let (reg, pi, mut rx_app) = meta_fixture().await;

        assert!(
            reg.update_room_meta(&pi, "main", RoomMetaPatch::default())
                .await
        );

        assert!(rx_app.try_recv().is_err());
        let rooms_snapshot = reg.rooms_of(&pi);
        assert_eq!(rooms_snapshot.len(), 1);
        assert!(!rooms_snapshot[0].working);
        assert!(rooms_snapshot[0].model.is_none());
        assert!(rooms_snapshot[0].thinking.is_none());
        assert!(rooms_snapshot[0].session_id.is_none());
    }

    /// `rooms_of` is the authoritative live-room snapshot and carries the
    /// latest projected `working` value after merge-patches.
    #[tokio::test]
    async fn rooms_of_returns_latest_working_projection() {
        let reg = make_registry();
        let pi = "pi".to_string();
        let (tx_pi, _rx_pi) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(pi.clone(), make_meta("main"), tx_pi).await;

        let rooms_snapshot = reg.rooms_of(&pi);
        assert_eq!(rooms_snapshot.len(), 1);
        assert_eq!(rooms_snapshot[0].working, false);

        assert!(
            reg.update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    working: Some(true),
                    ..Default::default()
                },
            )
            .await
        );
        let rooms_snapshot = reg.rooms_of(&pi);
        assert_eq!(rooms_snapshot.len(), 1);
        assert_eq!(rooms_snapshot[0].working, true);

        assert!(
            reg.update_room_meta(
                &pi,
                "main",
                RoomMetaPatch {
                    working: Some(false),
                    ..Default::default()
                },
            )
            .await
        );
        let rooms_snapshot = reg.rooms_of(&pi);
        assert_eq!(rooms_snapshot.len(), 1);
        assert_eq!(rooms_snapshot[0].working, false);
    }

    /// Disconnecting the last live conn ends the room: subscribers get one
    /// `room_ended`, and the next rooms snapshot omits that room entirely.
    /// App consumers gate their room projection on this live-room set, so any
    /// cached `working:true` for the ended room must render not-working.
    #[tokio::test]
    async fn unregister_last_conn_ends_room_and_removes_it_from_rooms_of() {
        let presence = Arc::new(PresenceManager::new());
        let rooms = Arc::new(RoomManager::new());
        let metrics = Arc::new(FirehoseMetrics::new());
        let reg = PeerRegistry::new(presence, rooms.clone(), metrics);

        let pi = "pi".to_string();
        let app = "app".to_string();

        let (tx_app, mut rx_app) = mpsc::unbounded_channel::<Message>();
        let _ = reg.register(app.clone(), make_meta("main"), tx_app).await;
        rooms.subscribe(app.clone(), vec![pi.clone()]).await;

        let (tx_pi, _rx_pi) = mpsc::unbounded_channel::<Message>();
        let mut meta = make_meta("main");
        meta.working = true;
        let conn = reg.register(pi.clone(), meta, tx_pi).await;
        let rooms_snapshot = reg.rooms_of(&pi);
        assert_eq!(rooms_snapshot.len(), 1);
        assert_eq!(rooms_snapshot[0].working, true);

        let announced = rx_app
            .try_recv()
            .expect("subscriber receives room_announced");
        let announced: serde_json::Value =
            serde_json::from_str(announced.to_text().unwrap()).unwrap();
        assert_eq!(announced["type"], "room_announced");
        assert_eq!(announced["working"], true);

        reg.unregister(&pi, "main", conn).await;

        let ended = rx_app.try_recv().expect("subscriber receives room_ended");
        let ended: serde_json::Value = serde_json::from_str(ended.to_text().unwrap()).unwrap();
        assert_eq!(ended["type"], "room_ended");
        assert_eq!(ended["peer"], pi);
        assert_eq!(ended["room_id"], "main");
        assert!(reg.rooms_of(&pi).is_empty());
    }
}
