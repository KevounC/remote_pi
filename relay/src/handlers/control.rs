use serde_json::{Map, Value};
use thiserror::Error;
use tracing::warn;

use crate::handlers::peer::MAX_CONTROL_FRAME_PEERS;
use crate::handlers::peer::connection_actor::{ActorDispatch, ConnectionActor};
use crate::protocol::generated::control::RelayControlFrame;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ControlFrameError {
    #[error("control frame {frame_type} requested {requested} peers, limit is {limit}")]
    TooManyPeers {
        frame_type: String,
        requested: usize,
        limit: usize,
    },
    #[error("control frame {frame_type} peers field must be an array")]
    PeersNotArray { frame_type: String },
    #[error("control frame {frame_type} peers[{index}] must be a string")]
    PeerNotString { frame_type: String, index: usize },
}

/// Validates the peer-list shape shared by presence/rooms control frames.
///
/// This is the fail-closed boundary that generated control-frame decoding calls
/// before mutating subscription state. Missing `peers` defaults to the canonical
/// empty list; malformed or oversized values are dropped by the typed handler.
pub fn bounded_peer_list(
    frame_type: &str,
    peers: Option<&serde_json::Value>,
) -> Result<Vec<String>, ControlFrameError> {
    let Some(peers_value) = peers else {
        return Ok(Vec::new());
    };
    let Some(peer_array) = peers_value.as_array() else {
        return Err(ControlFrameError::PeersNotArray {
            frame_type: frame_type.to_owned(),
        });
    };
    if peer_array.len() > MAX_CONTROL_FRAME_PEERS {
        return Err(ControlFrameError::TooManyPeers {
            frame_type: frame_type.to_owned(),
            requested: peer_array.len(),
            limit: MAX_CONTROL_FRAME_PEERS,
        });
    }

    let mut out = Vec::with_capacity(peer_array.len());
    for (index, value) in peer_array.iter().enumerate() {
        let Some(peer) = value.as_str() else {
            return Err(ControlFrameError::PeerNotString {
                frame_type: frame_type.to_owned(),
                index,
            });
        };
        out.push(peer.to_owned());
    }
    Ok(out)
}

pub(crate) fn is_presence_rooms_control_frame(frame_type: &str) -> bool {
    matches!(
        frame_type,
        "subscribe_presence"
            | "unsubscribe_presence"
            | "presence_check"
            | "subscribe_rooms"
            | "unsubscribe_rooms"
            | "rooms_check"
    )
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
            RelayControlFrame::SubscribePresence { fields } => {
                self.subscribe_presence(fields).await
            }
            RelayControlFrame::UnsubscribePresence { fields } => {
                self.unsubscribe_presence(fields).await
            }
            RelayControlFrame::PresenceCheck { fields } => self.presence_check(fields).await,
            RelayControlFrame::SubscribeRooms { fields } => self.subscribe_rooms(fields).await,
            RelayControlFrame::UnsubscribeRooms { fields } => self.unsubscribe_rooms(fields).await,
            RelayControlFrame::RoomsCheck { fields } => self.rooms_check(fields).await,
            _ => {
                warn!(
                    peer = %self.actor.peer_short,
                    "unsupported relay control frame reached presence/rooms handler, dropping"
                );
                ActorDispatch::Continue
            }
        }
    }

    async fn subscribe_presence(&mut self, fields: Map<String, Value>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("subscribe_presence", &fields) else {
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

    async fn unsubscribe_presence(&mut self, fields: Map<String, Value>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("unsubscribe_presence", &fields) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .presence
            .unsubscribe(&self.actor.peer_id, peers)
            .await;
        ActorDispatch::Continue
    }

    async fn presence_check(&mut self, fields: Map<String, Value>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("presence_check", &fields) else {
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

    async fn subscribe_rooms(&mut self, fields: Map<String, Value>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("subscribe_rooms", &fields) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .rooms
            .subscribe(self.actor.peer_id.clone(), peers)
            .await;
        ActorDispatch::Continue
    }

    async fn unsubscribe_rooms(&mut self, fields: Map<String, Value>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("unsubscribe_rooms", &fields) else {
            return ActorDispatch::Continue;
        };
        self.actor
            .rooms
            .unsubscribe(&self.actor.peer_id, peers)
            .await;
        ActorDispatch::Continue
    }

    async fn rooms_check(&mut self, fields: Map<String, Value>) -> ActorDispatch {
        let Some(peers) = self.bounded_peers("rooms_check", &fields) else {
            return ActorDispatch::Continue;
        };
        if !self.actor.allow_control_check("rooms_check", &peers) {
            return ActorDispatch::Continue;
        }
        self.actor.emit_deduped_room_snapshots(peers)
    }

    fn bounded_peers(&self, frame_type: &str, fields: &Map<String, Value>) -> Option<Vec<String>> {
        match bounded_peer_list(frame_type, fields.get("peers")) {
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
            Err(err) => {
                warn!(
                    peer = %self.actor.peer_short,
                    frame_type = %frame_type,
                    err = %err,
                    "malformed control frame peer list, dropping"
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
    use crate::protocol::generated::control::RelayControlFrame;
    use crate::rooms::{RoomManager, RoomMeta};

    fn fields(value: serde_json::Value) -> serde_json::Map<String, serde_json::Value> {
        value.as_object().expect("fields object").clone()
    }

    fn make_meta(room_id: &str) -> RoomMeta {
        RoomMeta {
            room_id: room_id.into(),
            name: None,
            cwd: None,
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
                self.registry.clone(),
                self.presence.clone(),
                self.rooms.clone(),
                self.metrics.clone(),
            )
        }
    }

    #[test]
    fn missing_peers_defaults_to_empty_list() {
        assert_eq!(
            bounded_peer_list("subscribe_presence", None),
            Ok(Vec::new())
        );
    }

    #[test]
    fn rejects_non_array_peer_list() {
        assert_eq!(
            bounded_peer_list("subscribe_presence", Some(&json!("peer-a"))),
            Err(ControlFrameError::PeersNotArray {
                frame_type: "subscribe_presence".to_owned()
            }),
        );
    }

    #[test]
    fn rejects_mixed_type_peer_list() {
        assert_eq!(
            bounded_peer_list("subscribe_presence", Some(&json!(["peer-a", 1]))),
            Err(ControlFrameError::PeerNotString {
                frame_type: "subscribe_presence".to_owned(),
                index: 1
            }),
        );
    }

    #[test]
    fn enforces_peer_limit() {
        let peers = (0..=MAX_CONTROL_FRAME_PEERS)
            .map(|idx| format!("peer-{idx}"))
            .collect::<Vec<_>>();
        assert!(matches!(
            bounded_peer_list("presence_check", Some(&json!(peers))),
            Err(ControlFrameError::TooManyPeers { requested, .. }) if requested == MAX_CONTROL_FRAME_PEERS + 1
        ));
    }

    #[tokio::test]
    async fn malformed_subscribe_presence_does_not_mutate_subscriptions() {
        let fixture = Fixture::new();
        let mut actor = fixture.actor("app");

        let dispatch = actor
            .dispatch_control(RelayControlFrame::SubscribePresence {
                fields: fields(json!({"peers": "pi"})),
            })
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        assert!(fixture.presence.subscribers_of("pi").await.is_empty());
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
                fields: fields(json!({"peers": ["pi"]})),
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
    async fn presence_check_dedup_and_metrics_live_in_actor() {
        let fixture = Fixture::new();
        let mut actor = fixture.actor("app");
        let frame = || RelayControlFrame::PresenceCheck {
            fields: fields(json!({"peers": ["pi"]})),
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
            fields: fields(json!({"peers": ["pi"]})),
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
