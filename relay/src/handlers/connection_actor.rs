use std::collections::HashMap;
use std::sync::Arc;

use tokio::time::{self, Duration};
use tracing::warn;

use crate::handlers::pi_forward::{
    MeshAuthCache, PiForwardResult, handle_malformed_pi_envelope, handle_pi_envelope,
};
use crate::mesh::MeshStore;
use crate::metrics::FirehoseMetrics;
use crate::peers::connections::ConnectionRegistry;
use crate::peers::registry::PeerRegistry;
use crate::peers::registry_event_publisher::RegistryEventPublisher;
use crate::peers::rooms::RoomStateStore;
use crate::presence::{PeerPresence, PresenceManager};
use crate::protocol::frame::{DecodedRelayFrame, PiEnvelopeFrame};
use crate::protocol::outer::OuterEnvelope;
use crate::rooms::RoomManager;

use crate::handlers::peer::{MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW, MAX_CONTROL_FRAME_PEERS};

const CONTROL_CHECK_PEER_COST_WINDOW: Duration = Duration::from_secs(60);

#[derive(Debug)]
pub(crate) enum ActorDispatch {
    Continue,
    #[allow(dead_code)]
    Close,
    Send(String),
    SendMany(Vec<String>),
}

#[derive(Debug)]
pub(crate) struct ControlCheckLimiter {
    window_started: time::Instant,
    peer_cost_used: usize,
}

impl ControlCheckLimiter {
    fn new() -> Self {
        Self {
            window_started: time::Instant::now(),
            peer_cost_used: 0,
        }
    }

    fn allow(&mut self, peer_cost: usize) -> bool {
        let now = time::Instant::now();
        if now.duration_since(self.window_started) >= CONTROL_CHECK_PEER_COST_WINDOW {
            self.window_started = now;
            self.peer_cost_used = 0;
        }

        let Some(next_cost) = self.peer_cost_used.checked_add(peer_cost) else {
            return false;
        };
        if next_cost > MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW {
            return false;
        }
        self.peer_cost_used = next_cost;
        true
    }
}

pub(crate) fn control_check_cost(peers: &[String]) -> usize {
    peers.len().max(1)
}

#[derive(Clone)]
pub(crate) struct ConnectionActorServices {
    pub(crate) registry: Arc<PeerRegistry>,
    pub(crate) presence: Arc<PresenceManager>,
    pub(crate) rooms: Arc<RoomManager>,
    pub(crate) mesh: Arc<MeshStore>,
    pub(crate) mesh_auth: Arc<MeshAuthCache>,
    pub(crate) metrics: Arc<FirehoseMetrics>,
}

pub(crate) struct ConnectionActor {
    pub(crate) peer_id: String,
    pub(crate) peer_short: String,
    pub(crate) room_id: String,
    conn_id: u64,
    pub(crate) delivery: Arc<ConnectionRegistry>,
    pub(crate) room_state: Arc<RoomStateStore>,
    pub(crate) events: Arc<RegistryEventPublisher>,
    pub(crate) presence: Arc<PresenceManager>,
    pub(crate) rooms: Arc<RoomManager>,
    mesh: Arc<MeshStore>,
    mesh_auth: Arc<MeshAuthCache>,
    metrics: Arc<FirehoseMetrics>,
    last_presence_resp: Option<String>,
    last_rooms_resp: HashMap<String, String>,
    control_check_limiter: ControlCheckLimiter,
}

impl ConnectionActor {
    pub(crate) fn new(
        peer_id: String,
        peer_short: String,
        room_id: String,
        conn_id: u64,
        services: ConnectionActorServices,
    ) -> Self {
        Self {
            peer_id,
            peer_short,
            room_id,
            conn_id,
            delivery: services.registry.connections(),
            room_state: services.registry.rooms(),
            events: services.registry.events(),
            presence: services.presence,
            rooms: services.rooms,
            mesh: services.mesh,
            mesh_auth: services.mesh_auth,
            metrics: services.metrics,
            last_presence_resp: None,
            last_rooms_resp: HashMap::new(),
            control_check_limiter: ControlCheckLimiter::new(),
        }
    }

    pub(crate) async fn dispatch(&mut self, frame: DecodedRelayFrame) -> ActorDispatch {
        match frame {
            DecodedRelayFrame::Outer(frame) => self.dispatch_outer(frame).await,
            DecodedRelayFrame::Control(frame) => self.dispatch_control(frame).await,
            DecodedRelayFrame::PiEnvelope(frame) => self.dispatch_pi_envelope(frame).await,
            DecodedRelayFrame::MalformedPiEnvelope(frame) => {
                self.dispatch_malformed_pi_envelope(frame).await
            }
        }
    }

    async fn dispatch_outer(&mut self, env: OuterEnvelope) -> ActorDispatch {
        let ct_len = env.ct.len();
        let dest_peer = env.peer;
        let dest_room = env.room;
        let dest_tail = dest_peer[dest_peer.len().saturating_sub(8)..].to_string();

        // Rewrite: recipient sees sender's authenticated peer_id + sender's room_id.
        let rewritten = OuterEnvelope {
            peer: self.peer_id.clone(),
            room: self.room_id.clone(),
            ct: env.ct,
        };
        let fwd_line = rewritten.to_json_string();

        // Skip-sender: pass this connection's conn_id so multi-device Owners
        // don't echo their own outbound messages.
        if !self.delivery.send_to_room(
            &dest_peer,
            &dest_room,
            axum::extract::ws::Message::Text(fwd_line),
            self.conn_id,
        ) {
            warn!(
                from = %self.peer_short,
                dest = %dest_tail,
                room = %dest_room,
                bytes = ct_len,
                "dest (peer, room) not found, dropping",
            );
        }

        ActorDispatch::Continue
    }

    async fn dispatch_pi_envelope(&mut self, frame: PiEnvelopeFrame) -> ActorDispatch {
        self.pi_forward_result_to_dispatch(
            handle_pi_envelope(
                &self.peer_id,
                self.conn_id,
                &self.room_id,
                frame,
                &self.delivery,
                &self.mesh,
                &self.mesh_auth,
            )
            .await,
        )
    }

    async fn dispatch_malformed_pi_envelope(&mut self, frame: serde_json::Value) -> ActorDispatch {
        self.pi_forward_result_to_dispatch(handle_malformed_pi_envelope(&frame, &self.room_id))
    }

    fn pi_forward_result_to_dispatch(&self, result: PiForwardResult) -> ActorDispatch {
        match result {
            PiForwardResult::Forwarded => ActorDispatch::Continue,
            PiForwardResult::TransportError(message) => match message {
                axum::extract::ws::Message::Text(text) => ActorDispatch::Send(text),
                _ => ActorDispatch::Continue,
            },
        }
    }

    pub(crate) fn allow_control_check(&mut self, frame_type: &str, peers: &[String]) -> bool {
        let cost = control_check_cost(peers);
        if self.control_check_limiter.allow(cost) {
            return true;
        }

        warn!(
            peer = %self.peer_short,
            frame_type = %frame_type,
            cost,
            limit = MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW,
            window_secs = CONTROL_CHECK_PEER_COST_WINDOW.as_secs(),
            max_peers_per_frame = MAX_CONTROL_FRAME_PEERS,
            "control frame check rate limit exceeded, dropping"
        );
        false
    }

    pub(crate) fn emit_deduped_presence(&mut self, states: Vec<PeerPresence>) -> ActorDispatch {
        let resp = serde_json::json!({
            "type": "presence",
            "states": states,
        })
        .to_string();

        if self.last_presence_resp.as_deref() == Some(resp.as_str()) {
            self.metrics.inc_presence_suppressed(1);
            ActorDispatch::Continue
        } else {
            self.last_presence_resp = Some(resp.clone());
            self.metrics.inc_presence_emitted(1);
            ActorDispatch::Send(resp)
        }
    }

    pub(crate) fn emit_deduped_room_snapshots(&mut self, peers: Vec<String>) -> ActorDispatch {
        let mut messages = Vec::new();
        for target_peer in peers {
            let active_rooms = self.room_state.rooms_of(&target_peer);
            let resp = serde_json::json!({
                "type": "rooms",
                "peer": target_peer,
                "rooms": active_rooms,
            })
            .to_string();

            if self.last_rooms_resp.get(&target_peer) == Some(&resp) {
                self.metrics.inc_rooms_suppressed(1);
                continue;
            }

            self.last_rooms_resp.insert(target_peer, resp.clone());
            self.metrics.inc_rooms_emitted(1);
            messages.push(resp);
        }

        if messages.is_empty() {
            ActorDispatch::Continue
        } else {
            ActorDispatch::SendMany(messages)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::extract::ws::Message;
    use tokio::sync::mpsc;

    use crate::metrics::FirehoseMetrics;
    use crate::peers::registry::PeerRegistry;
    use crate::presence::PresenceManager;
    use crate::protocol::frame::{FrameDecodeError, RelayControlFrame, decode_relay_frame};
    use crate::protocol::generated::control::{RELAY_CONTROL_FRAME_TYPES, RoomMetaUpdateFrame};
    use crate::rooms::{RoomManager, RoomMeta, RoomMetaPatch};

    fn actor_services() -> (Arc<PeerRegistry>, ConnectionActorServices) {
        let presence = Arc::new(PresenceManager::new());
        let rooms = Arc::new(RoomManager::new());
        let metrics = Arc::new(FirehoseMetrics::new());
        let registry = Arc::new(PeerRegistry::new(
            presence.clone(),
            rooms.clone(),
            metrics.clone(),
        ));
        let services = ConnectionActorServices {
            registry: registry.clone(),
            presence,
            rooms,
            mesh: Arc::new(MeshStore::open_in_memory().unwrap()),
            mesh_auth: Arc::new(MeshAuthCache::new()),
            metrics,
        };
        (registry, services)
    }

    fn make_meta(room_id: &str) -> RoomMeta {
        RoomMeta {
            room_id: room_id.to_string(),
            name: None,
            cwd: None,
            session_id: None,
            model: None,
            thinking: None,
            working: false,
            started_at: 0,
        }
    }

    fn text_from_rx(rx: &mut mpsc::UnboundedReceiver<Message>) -> String {
        rx.try_recv()
            .expect("recipient must receive forwarded envelope")
            .to_text()
            .expect("forwarded envelope must be text")
            .to_string()
    }

    #[tokio::test]
    async fn dispatch_malformed_pi_envelope_returns_bad_envelope_transport_error() {
        let (_, services) = actor_services();
        let mut actor = ConnectionActor::new(
            "sender-peer".to_string(),
            "der-peer".to_string(),
            "sender-room".to_string(),
            42,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::MalformedPiEnvelope(serde_json::json!({
                "type": "pi_envelope",
                "envelope": {
                    "from": "a:sess",
                    "to": "b:agent",
                    "id": "018f4444-4444-7444-8444-444444444444",
                    "re": null,
                    "body": { "type": "ping", "session_id": "opaque-session" }
                }
            })))
            .await;

        let ActorDispatch::Send(text) = dispatch else {
            panic!("malformed pi_envelope must send a transport_error");
        };
        let frame: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(frame["type"], "pi_envelope_in");
        assert_eq!(frame["from_pc"], "_relay");
        assert_eq!(frame["envelope"]["from"], "_relay");
        assert_eq!(frame["envelope"]["to"], "a:sess");
        assert_eq!(
            frame["envelope"]["re"],
            "018f4444-4444-7444-8444-444444444444"
        );
        assert_eq!(frame["envelope"]["body"]["type"], "transport_error");
        assert_eq!(frame["envelope"]["body"]["reason"], "bad_envelope");
    }

    #[test]
    fn constructs_with_per_connection_state_empty() {
        let actor = ConnectionActor::new(
            "peer-12345678".to_string(),
            "12345678".to_string(),
            "main".to_string(),
            42,
            actor_services().1,
        );

        assert_eq!(actor.peer_id, "peer-12345678");
        assert_eq!(actor.peer_short, "12345678");
        assert_eq!(actor.room_id, "main");
        assert_eq!(actor.conn_id, 42);
        assert!(actor.last_presence_resp.is_none());
        assert!(actor.last_rooms_resp.is_empty());
        assert_eq!(actor.control_check_limiter.peer_cost_used, 0);
    }

    #[test]
    fn control_check_limiter_counts_peer_cost_and_rejects_over_budget() {
        let mut limiter = ControlCheckLimiter::new();

        assert!(limiter.allow(MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW));
        assert!(!limiter.allow(1));
    }

    #[test]
    fn control_check_cost_charges_empty_checks() {
        assert_eq!(control_check_cost(&[]), 1);
    }

    #[test]
    fn generated_control_dispatch_coverage_tracks_all_variants() {
        let covered_variants = [
            RelayControlFrame::SubscribePresence { peers: Vec::new() },
            RelayControlFrame::UnsubscribePresence { peers: Vec::new() },
            RelayControlFrame::PresenceCheck { peers: Vec::new() },
            RelayControlFrame::SubscribeRooms { peers: Vec::new() },
            RelayControlFrame::UnsubscribeRooms { peers: Vec::new() },
            RelayControlFrame::RoomsCheck { peers: Vec::new() },
            RelayControlFrame::RoomMetaUpdate(RoomMetaUpdateFrame {
                room_id: None,
                meta: RoomMetaPatch::default(),
            }),
        ];

        assert_eq!(covered_variants.len(), RELAY_CONTROL_FRAME_TYPES.len());
    }

    #[test]
    fn malformed_control_peers_reject_at_decode_boundary() {
        let err = decode_relay_frame(r#"{"type":"subscribe_presence","peers":"pi"}"#)
            .expect_err("malformed control frame must fail before dispatch");

        assert!(matches!(err, FrameDecodeError::InvalidJson(_)));
    }

    #[test]
    fn empty_control_peers_remain_valid_at_decode_boundary() {
        let frame = decode_relay_frame(r#"{"type":"presence_check","peers":[]}"#)
            .expect("empty peer list is a valid typed control frame");

        assert!(matches!(
            frame,
            DecodedRelayFrame::Control(RelayControlFrame::PresenceCheck { peers })
                if peers.is_empty()
        ));
    }

    #[tokio::test]
    async fn dispatch_routes_control_frames_to_typed_handler() {
        let (_, services) = actor_services();
        let mut actor = ConnectionActor::new(
            "app".to_string(),
            "app".to_string(),
            "main".to_string(),
            42,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Control(
                RelayControlFrame::PresenceCheck {
                    peers: vec!["pi".to_string()],
                },
            ))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Send(_)));
    }

    #[tokio::test]
    async fn dispatch_outer_forwards_ct_verbatim_and_rewrites_sender_identity() {
        let (registry, services) = actor_services();
        let (dest_tx, mut dest_rx) = mpsc::unbounded_channel::<Message>();
        let _dest_conn = registry
            .register("dest-peer".to_string(), make_meta("dest-room"), dest_tx)
            .await;

        let mut actor = ConnectionActor::new(
            "sender-peer".to_string(),
            "der-peer".to_string(),
            "sender-room".to_string(),
            42,
            services,
        );
        let opaque_ct = "eyJ0eXBlIjoidXNlcl9tZXNzYWdlIiwidGV4dCI6ImRvIG5vdCBkZWNvZGUifQ==";

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Outer(OuterEnvelope {
                peer: "dest-peer".to_string(),
                room: "dest-room".to_string(),
                ct: opaque_ct.to_string(),
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        let delivered: OuterEnvelope = serde_json::from_str(&text_from_rx(&mut dest_rx)).unwrap();
        assert_eq!(delivered.peer, "sender-peer");
        assert_eq!(delivered.room, "sender-room");
        assert_eq!(delivered.ct, opaque_ct);
    }

    #[tokio::test]
    async fn dispatch_outer_targets_exact_destination_room_without_cross_room_contamination() {
        let (registry, services) = actor_services();
        let (target_tx, mut target_rx) = mpsc::unbounded_channel::<Message>();
        let (other_tx, mut other_rx) = mpsc::unbounded_channel::<Message>();
        let _target_conn = registry
            .register("dest-peer".to_string(), make_meta("target-room"), target_tx)
            .await;
        let _other_conn = registry
            .register("dest-peer".to_string(), make_meta("other-room"), other_tx)
            .await;

        let mut actor = ConnectionActor::new(
            "sender-peer".to_string(),
            "der-peer".to_string(),
            "sender-room".to_string(),
            42,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Outer(OuterEnvelope {
                peer: "dest-peer".to_string(),
                room: "target-room".to_string(),
                ct: "opaque-bytes".to_string(),
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        let delivered: OuterEnvelope = serde_json::from_str(&text_from_rx(&mut target_rx)).unwrap();
        assert_eq!(delivered.ct, "opaque-bytes");
        assert!(
            other_rx.try_recv().is_err(),
            "outer forwarding must not leak into sibling rooms for the same peer"
        );
    }

    #[tokio::test]
    async fn dispatch_outer_skips_sender_connection_without_suppressing_other_matching_connections()
    {
        let (registry, services) = actor_services();
        let (sender_tx, mut sender_rx) = mpsc::unbounded_channel::<Message>();
        let (other_tx, mut other_rx) = mpsc::unbounded_channel::<Message>();
        let sender_conn = registry
            .register("owner-peer".to_string(), make_meta("main"), sender_tx)
            .await;
        let _other_conn = registry
            .register("owner-peer".to_string(), make_meta("main"), other_tx)
            .await;

        let mut actor = ConnectionActor::new(
            "owner-peer".to_string(),
            "ner-peer".to_string(),
            "main".to_string(),
            sender_conn,
            services,
        );

        let dispatch = actor
            .dispatch(DecodedRelayFrame::Outer(OuterEnvelope {
                peer: "owner-peer".to_string(),
                room: "main".to_string(),
                ct: "same-room-opaque".to_string(),
            }))
            .await;

        assert!(matches!(dispatch, ActorDispatch::Continue));
        assert!(
            sender_rx.try_recv().is_err(),
            "originating connection must not receive its own forwarded envelope"
        );
        let delivered: OuterEnvelope = serde_json::from_str(&text_from_rx(&mut other_rx)).unwrap();
        assert_eq!(delivered.peer, "owner-peer");
        assert_eq!(delivered.room, "main");
        assert_eq!(delivered.ct, "same-room-opaque");
    }
}
