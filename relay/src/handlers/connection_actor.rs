use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::ws::Message;
use tokio::time::{self, Duration};
use tracing::warn;

use crate::metrics::FirehoseMetrics;
use crate::peers::registry::PeerRegistry;
use crate::presence::{PeerPresence, PresenceManager};
use crate::rooms::RoomManager;

use super::{MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW, MAX_CONTROL_FRAME_PEERS};

const CONTROL_CHECK_PEER_COST_WINDOW: Duration = Duration::from_secs(60);

#[derive(Debug)]
pub(crate) enum ActorDispatch {
    Continue,
    Send(Message),
    SendMany(Vec<Message>),
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

pub(crate) struct ConnectionActor {
    pub(crate) peer_id: String,
    pub(crate) peer_short: String,
    pub(crate) room_id: String,
    pub(crate) registry: Arc<PeerRegistry>,
    pub(crate) presence: Arc<PresenceManager>,
    pub(crate) rooms: Arc<RoomManager>,
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
        registry: Arc<PeerRegistry>,
        presence: Arc<PresenceManager>,
        rooms: Arc<RoomManager>,
        metrics: Arc<FirehoseMetrics>,
    ) -> Self {
        Self {
            peer_id,
            peer_short,
            room_id,
            registry,
            presence,
            rooms,
            metrics,
            last_presence_resp: None,
            last_rooms_resp: HashMap::new(),
            control_check_limiter: ControlCheckLimiter::new(),
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
            ActorDispatch::Send(Message::Text(resp))
        }
    }

    pub(crate) fn emit_deduped_room_snapshots(&mut self, peers: Vec<String>) -> ActorDispatch {
        let mut messages = Vec::new();
        for target_peer in peers {
            let active_rooms = self.registry.rooms_of(&target_peer);
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
            messages.push(Message::Text(resp));
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
}
