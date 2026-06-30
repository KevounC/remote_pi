use thiserror::Error;
use tracing::warn;

use crate::handlers::peer::MAX_CONTROL_FRAME_PEERS;
use crate::handlers::peer::connection_actor::{ActorDispatch, ConnectionActor};
use crate::protocol::generated::control::{RelayControlFrame, RoomMetaUpdateFrame};

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ControlFrameError {
    #[error("control frame {frame_type} requested {requested} peers, limit is {limit}")]
    TooManyPeers {
        frame_type: String,
        requested: usize,
        limit: usize,
    },
}

/// Validates the peer-list shape shared by presence/rooms control frames.
///
/// This is the fail-closed boundary that generated control-frame decoding calls
/// before mutating subscription state. Missing `peers` defaults to the canonical
/// empty list; malformed or oversized values are dropped by the typed handler.
pub fn bounded_peer_list(
    frame_type: &str,
    peers: Vec<String>,
) -> Result<Vec<String>, ControlFrameError> {
    if peers.len() > MAX_CONTROL_FRAME_PEERS {
        return Err(ControlFrameError::TooManyPeers {
            frame_type: frame_type.to_owned(),
            requested: peers.len(),
            limit: MAX_CONTROL_FRAME_PEERS,
        });
    }

    Ok(peers)
}

pub(crate) struct ControlHandlers<'actor> {
    actor: &'actor mut ConnectionActor,
}

impl ConnectionActor {
    pub(crate) async fn dispatch_control(&mut self, frame: RelayControlFrame) -> ActorDispatch {
        ControlHandlers::new(self).handle(frame).await
    }
}

impl<'actor> ControlHandlers<'actor> {
    pub(crate) fn new(actor: &'actor mut ConnectionActor) -> Self {
        Self { actor }
    }

    pub(crate) async fn handle(&mut self, frame: RelayControlFrame) -> ActorDispatch {
        match frame {
            RelayControlFrame::SubscribePresence { peers } => self.subscribe_presence(peers).await,
            RelayControlFrame::UnsubscribePresence { peers } => {
                self.unsubscribe_presence(peers).await
            }
            RelayControlFrame::PresenceCheck { peers } => self.presence_check(peers).await,
            RelayControlFrame::SubscribeRooms { peers } => self.subscribe_rooms(peers).await,
            RelayControlFrame::UnsubscribeRooms { peers } => self.unsubscribe_rooms(peers).await,
            RelayControlFrame::RoomsCheck { peers } => self.rooms_check(peers).await,
            RelayControlFrame::RoomMetaUpdate(frame) => self.room_meta_update(frame).await,
        }
    }

    async fn subscribe_presence(&mut self, peers: Vec<String>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("subscribe_presence", peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .presence
            .subscribe(self.actor.peer_id.clone(), peers.clone())
            .await;
        self.actor
            .registry
            .backfill_presence(&self.actor.peer_id, &peers);
        ActorDispatch::Continue
    }

    async fn unsubscribe_presence(&mut self, peers: Vec<String>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("unsubscribe_presence", peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .presence
            .unsubscribe(&self.actor.peer_id, peers)
            .await;
        ActorDispatch::Continue
    }

    async fn presence_check(&mut self, peers: Vec<String>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("presence_check", peers) else {
            return ActorDispatch::Continue;
        };
        if !self.actor.allow_control_check("presence_check", &peers) {
            return ActorDispatch::Continue;
        }
        let states = self
            .actor
            .presence
            .snapshot(&peers, |p| self.actor.registry.is_online(p))
            .await;
        self.actor.emit_deduped_presence(states)
    }

    async fn subscribe_rooms(&mut self, peers: Vec<String>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("subscribe_rooms", peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .rooms
            .subscribe(self.actor.peer_id.clone(), peers)
            .await;
        ActorDispatch::Continue
    }

    async fn unsubscribe_rooms(&mut self, peers: Vec<String>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("unsubscribe_rooms", peers) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .rooms
            .unsubscribe(&self.actor.peer_id, peers)
            .await;
        ActorDispatch::Continue
    }

    async fn rooms_check(&mut self, peers: Vec<String>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("rooms_check", peers) else {
            return ActorDispatch::Continue;
        };
        if !self.actor.allow_control_check("rooms_check", &peers) {
            return ActorDispatch::Continue;
        }
        self.actor.emit_deduped_room_snapshots(peers)
    }

    async fn room_meta_update(&mut self, frame: RoomMetaUpdateFrame) -> ActorDispatch {
        let target_room = frame.room_id.unwrap_or_else(|| self.actor.room_id.clone());
        if !self
            .actor
            .registry
            .update_room_meta(&self.actor.peer_id, &target_room, frame.meta)
            .await
        {
            warn!(
                peer = %self.actor.peer_short,
                room = %target_room,
                "room_meta_update for unknown (peer, room), dropping"
            );
        }
        ActorDispatch::Continue
    }

    fn bounded_peers(&self, frame_type: &str, peers: Vec<String>) -> Option<Vec<String>> {
        match bounded_peer_list(frame_type, peers) {
            Ok(peers) => Some(peers),
            Err(ControlFrameError::TooManyPeers {
                requested, limit, ..
            }) => {
                warn!(
                    peer = %self.actor.peer_short,
                    frame_type = %frame_type,
                    requested_peers = requested,
                    limit,
                    "control frame peer limit exceeded, dropping"
                );
                None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use axum::extract::ws::Message;
    use serde_json::json;
    use tokio::sync::mpsc;

    use super::{ControlFrameError, bounded_peer_list};
    use crate::handlers::peer::MAX_CONTROL_FRAME_PEERS;
    use crate::handlers::peer::connection_actor::{ActorDispatch, ConnectionActor};
    use crate::metrics::FirehoseMetrics;
    use crate::peers::registry::PeerRegistry;
    use crate::presence::PresenceManager;
    use crate::protocol::generated::control::{RelayControlFrame, RoomMetaUpdateFrame};
    use crate::rooms::{RoomManager, RoomMeta, RoomMetaPatch};

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

    struct Fixture {
        presence: Arc<PresenceManager>,
        rooms: Arc<RoomManager>,
        registry: Arc<PeerRegistry>,
        metrics: Arc<FirehoseMetrics>,
    }

    impl Fixture {
        fn new() -> Self {
            let presence = Arc::new(PresenceManager::new());
            let rooms = Arc::new(RoomManager::new());
            let metrics = Arc::new(FirehoseMetrics::new());
            let registry = Arc::new(PeerRegistry::new(
                presence.clone(),
                rooms.clone(),
                metrics.clone(),
            ));
            Self {
                presence,
                rooms,
                registry,
                metrics,
            }
        }

        fn actor(&self, peer_id: &str) -> ConnectionActor {
            ConnectionActor::new(
                peer_id.to_owned(),
                peer_id.to_owned(),
                "main".to_string(),
                self.registry.clone(),
                self.presence.clone(),
                self.rooms.clone(),
                self.metrics.clone(),
            )
        }
    }

    #[test]
    fn missing_peers_defaults_to_empty_list_at_generated_boundary() {
        let frame: RelayControlFrame = serde_json::from_value(json!({
            "type": "subscribe_presence"
        }))
        .expect("generated control frame parses default peers");

        assert!(
            matches!(frame, RelayControlFrame::SubscribePresence { peers } if peers.is_empty())
        );
    }

    #[test]
    fn rejects_non_array_peer_list_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "subscribe_presence",
            "peers": "peer-a"
        }))
        .expect_err("generated control frame rejects non-array peers");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn rejects_mixed_type_peer_list_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "subscribe_presence",
            "peers": ["peer-a", 1]
        }))
        .expect_err("generated control frame rejects non-string peers");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn rejects_malformed_room_meta_update_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "room_meta_update",
            "meta": []
        }))
        .expect_err("generated control frame rejects non-object meta");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn rejects_nullable_working_in_room_meta_update_at_generated_boundary() {
        let err = serde_json::from_value::<RelayControlFrame>(json!({
            "type": "room_meta_update",
            "meta": { "working": null }
        }))
        .expect_err("generated control frame rejects null working");

        assert!(err.to_string().contains("invalid type"));
    }

    #[test]
    fn parses_room_meta_update_with_generated_patch_type() {
        let frame: RelayControlFrame = serde_json::from_value(json!({
            "type": "room_meta_update",
            "meta": {
                "session_id": null,
                "working": false
            }
        }))
        .expect("generated room_meta_update parses");

        assert!(matches!(
            frame,
            RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame { meta, .. })
                if meta.session_id == Some(None) && meta.working == Some(false)
        ));
    }

    #[test]
    fn enforces_peer_limit() {
        let peers = (0..=MAX_CONTROL_FRAME_PEERS)
            .map(|idx| format!("peer-{idx}"))
            .collect::<Vec<_>>();
        assert!(matches!(
            bounded_peer_list("presence_check", peers),
            Err(ControlFrameError::TooManyPeers { requested, .. }) if requested == MAX_CONTROL_FRAME_PEERS + 1
        ));
    }

    #[tokio::test]
    async fn oversized_subscribe_presence_does_not_mutate_subscriptions() {
        let fixture = Fixture::new();
        let mut actor = fixture.actor("app");
        let peers = (0..=MAX_CONTROL_FRAME_PEERS)
            .map(|idx| format!("peer-{idx}"))
            .collect();

        let dispatch = actor
            .dispatch_control(RelayControlFrame::SubscribePresence { peers })
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        assert!(fixture.presence.subscribers_of("peer-0").await.is_empty());
    }

    #[tokio::test]
    async fn subscribe_presence_backfills_online_peers_from_handler() {
        let fixture = Fixture::new();
        let (tx_app, mut rx_app) = mpsc::unbounded_channel::<Message>();
        fixture
            .registry
            .register("app".into(), make_meta("main"), tx_app)
            .await;
        let (tx_pi, _rx_pi) = mpsc::unbounded_channel::<Message>();
        fixture
            .registry
            .register("pi".into(), make_meta("main"), tx_pi)
            .await;
        let mut actor = fixture.actor("app");

        let dispatch = actor
            .dispatch_control(RelayControlFrame::SubscribePresence {
                peers: vec!["pi".to_string()],
            })
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        assert!(
            fixture
                .presence
                .subscribers_of("pi")
                .await
                .contains(&"app".to_string())
        );
        let msg = rx_app.try_recv().expect("backfill peer_online");
        let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
        assert_eq!(v, json!({"type": "peer_online", "peer": "pi"}));
    }

    #[tokio::test]
    async fn room_meta_update_dispatches_through_typed_actor_handler() {
        let fixture = Fixture::new();
        let (tx_pi, _rx_pi) = mpsc::unbounded_channel::<Message>();
        fixture
            .registry
            .register("pi".into(), make_meta("main"), tx_pi)
            .await;
        let (tx_app, mut rx_app) = mpsc::unbounded_channel::<Message>();
        fixture
            .registry
            .register("app".into(), make_meta("main"), tx_app)
            .await;
        fixture
            .rooms
            .subscribe("app".into(), vec!["pi".to_string()])
            .await;
        let mut actor = fixture.actor("pi");

        let dispatch = actor
            .dispatch_control(RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame {
                room_id: None,
                meta: RoomMetaPatch {
                    working: Some(true),
                    ..Default::default()
                },
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        let msg = rx_app.try_recv().expect("room_meta_updated");
        let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
        assert_eq!(v["type"], "room_meta_updated");
        assert_eq!(v["peer"], "pi");
        assert_eq!(v["room_id"], "main");
        assert_eq!(v["meta"]["working"], true);
    }

    #[tokio::test]
    async fn presence_check_dedup_and_metrics_live_in_actor() {
        let fixture = Fixture::new();
        let mut actor = fixture.actor("app");
        let frame = || RelayControlFrame::PresenceCheck {
            peers: vec!["pi".to_string()],
        };

        let first = actor.dispatch_control(frame()).await;
        assert!(matches!(first, ActorDispatch::Send(Message::Text(_))));
        let second = actor.dispatch_control(frame()).await;
        assert!(matches!(second, ActorDispatch::Continue));

        let [_, _, presence_emitted, presence_suppressed, _, _] = fixture.metrics.snapshot();
        assert_eq!(presence_emitted, 1);
        assert_eq!(presence_suppressed, 1);
    }

    #[tokio::test]
    async fn rooms_check_dedup_and_metrics_live_in_actor() {
        let fixture = Fixture::new();
        let (tx_pi, _rx_pi) = mpsc::unbounded_channel::<Message>();
        fixture
            .registry
            .register("pi".into(), make_meta("main"), tx_pi)
            .await;
        let mut actor = fixture.actor("app");
        let frame = || RelayControlFrame::RoomsCheck {
            peers: vec!["pi".to_string()],
        };

        let first = actor.dispatch_control(frame()).await;
        assert!(matches!(first, ActorDispatch::SendMany(messages) if messages.len() == 1));
        let second = actor.dispatch_control(frame()).await;
        assert!(matches!(second, ActorDispatch::Continue));

        let [_, _, _, _, rooms_emitted, rooms_suppressed] = fixture.metrics.snapshot();
        assert_eq!(rooms_emitted, 1);
        assert_eq!(rooms_suppressed, 1);
    }
}
