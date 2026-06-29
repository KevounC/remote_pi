use std::collections::HashMap;
use std::net::SocketAddr;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, State};
use axum::response::Response;
use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio::time::{self, Duration};
use tracing::{info, warn};

use crate::AppState;
use crate::auth::challenge::{
    HELLO_TIMEOUT_MS, challenge_line, gen_nonce, parse_hello, verify_auth,
};
use crate::protocol::outer::{OuterEnvelope, parse_line};
use crate::rooms::{RoomMeta, RoomMetaPatch};

/// Maximum number of peer IDs accepted in one presence/rooms control frame.
/// The relay uses unbounded per-connection channels internally, so every frame
/// that can register subscriptions or request per-peer snapshots must have a
/// small, explicit fanout ceiling.
pub const MAX_CONTROL_FRAME_PEERS: usize = 64;

/// Maximum peer-cost a single WebSocket connection may spend on presence/rooms
/// check frames inside one limiter window. Empty checks still cost 1 so a peer
/// cannot spin free no-op requests indefinitely.
pub const MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW: usize = MAX_CONTROL_FRAME_PEERS * 4;
const CONTROL_CHECK_PEER_COST_WINDOW: Duration = Duration::from_secs(60);

#[derive(Debug)]
struct ControlCheckLimiter {
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

fn parse_bounded_control_peers(
    frame: &serde_json::Value,
    frame_type: &str,
    peer_short: &str,
) -> Option<Vec<String>> {
    let Some(peers_value) = frame.get("peers") else {
        return Some(Vec::new());
    };
    let Some(peer_array) = peers_value.as_array() else {
        warn!(
            peer = %peer_short,
            frame_type = %frame_type,
            "control frame peers field is not an array, using empty peer list"
        );
        return Some(Vec::new());
    };

    if peer_array.len() > MAX_CONTROL_FRAME_PEERS {
        warn!(
            peer = %peer_short,
            frame_type = %frame_type,
            requested_peers = peer_array.len(),
            limit = MAX_CONTROL_FRAME_PEERS,
            "control frame peer limit exceeded, dropping"
        );
        return None;
    }

    Some(
        peer_array
            .iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect(),
    )
}

fn control_check_cost(peers: &[String]) -> usize {
    peers.len().max(1)
}

/// Axum route handler: validates the WebSocket upgrade and hands the upgraded
/// socket to `handle_peer`, which owns the connection for its lifetime.
pub async fn ws_handler(
    ws: WebSocketUpgrade,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<AppState>,
) -> Response {
    ws.on_upgrade(move |socket| handle_peer(socket, addr, state))
}

/// Owns one peer's WebSocket connection: hello/challenge/auth → register →
/// routing loop (forwarding outer envelopes + handling presence/rooms control
/// frames + sending 25 s keepalive pings) → unregister on disconnect.
async fn handle_peer(socket: WebSocket, peer_addr: SocketAddr, state: AppState) {
    let peer_addr = peer_addr.to_string();
    let (mut sink, mut stream) = socket.split();

    // ── 1. Wait for hello (with timeout) ──────────────────────────────────
    let hello_result =
        tokio::time::timeout(Duration::from_millis(HELLO_TIMEOUT_MS), stream.next()).await;

    let hello_text = match hello_result {
        Ok(Some(Ok(Message::Text(t)))) => t,
        _ => {
            warn!(addr = %peer_addr, "no hello received, closing");
            return;
        }
    };

    let vk = match parse_hello(&hello_text) {
        Ok(vk) => vk,
        Err(e) => {
            warn!(addr = %peer_addr, err = %e, "bad hello, closing");
            return;
        }
    };

    // ── 2. Send challenge ─────────────────────────────────────────────────
    let (nonce, nonce_b64) = gen_nonce();
    if sink
        .send(Message::Text(challenge_line(&nonce_b64)))
        .await
        .is_err()
    {
        return;
    }

    // ── 3. Receive and verify auth ────────────────────────────────────────
    let auth_text = match stream.next().await {
        Some(Ok(Message::Text(t))) => t,
        _ => return,
    };

    if let Err(e) = verify_auth(&nonce, &vk, &auth_text) {
        warn!(addr = %peer_addr, err = %e, "auth failed, closing");
        let _ = sink.send(Message::Close(None)).await;
        return;
    }

    let peer_id = B64.encode(vk.to_bytes());
    let peer_short = peer_id[peer_id.len().saturating_sub(8)..].to_string();

    // Extract room_id and room_meta from hello (auth handled separately above).
    let room_meta = {
        let hello: serde_json::Value =
            serde_json::from_str(&hello_text).unwrap_or(serde_json::Value::Null);
        let room_id = hello
            .get("room_id")
            .and_then(|v| v.as_str())
            .unwrap_or("main")
            .to_string();
        let room_meta_val = hello.get("room_meta");
        let name = room_meta_val
            .and_then(|m| m.get("name"))
            .and_then(|v| v.as_str())
            .map(String::from);
        let cwd = room_meta_val
            .and_then(|m| m.get("cwd"))
            .and_then(|v| v.as_str())
            .map(String::from);
        let session_id = room_meta_val
            .and_then(|m| m.get("session_id"))
            .and_then(|v| v.as_str())
            .map(String::from);
        let model = room_meta_val
            .and_then(|m| m.get("model"))
            .and_then(|v| v.as_str())
            .map(String::from);
        let thinking = room_meta_val
            .and_then(|m| m.get("thinking"))
            .and_then(|v| v.as_str())
            .map(String::from);
        let working = room_meta_val
            .and_then(|m| m.get("working"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let started_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as i64;
        RoomMeta {
            room_id,
            name,
            cwd,
            session_id,
            model,
            thinking,
            working,
            started_at,
        }
    };
    let room_id = room_meta.room_id.clone();

    info!(peer = %peer_short, room = %room_id, addr = %peer_addr, "authenticated");

    let registry = state.registry.clone();
    let presence = state.presence.clone();
    let rooms = state.rooms.clone();
    let mesh = state.mesh.clone();
    let mesh_auth = state.mesh_auth.clone();
    let metrics = state.metrics.clone();

    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();
    let conn_id = registry.register(peer_id.clone(), room_meta, tx).await;

    // Per-conn dedup state for control-frame replies. Suppress identical
    // re-emits of `presence` (single cache slot — there's only one
    // subscription set per conn) and `rooms` (one slot per target peer).
    let mut last_presence_resp: Option<String> = None;
    let mut last_rooms_resp: HashMap<String, String> = HashMap::new();
    let mut control_check_limiter = ControlCheckLimiter::new();

    // ── 4. Routing loop ───────────────────────────────────────────────────
    // Send a WS Ping every 25 s so NAT/LB idle timers don't close the connection.
    // First tick fires after 25 s (not immediately).
    let mut heartbeat = time::interval_at(
        time::Instant::now() + Duration::from_secs(25),
        Duration::from_secs(25),
    );

    'routing: loop {
        tokio::select! {
            item = stream.next() => {
                match item {
                    None | Some(Err(_)) => break,
                    Some(Ok(msg)) => {
                        let text = match msg {
                            Message::Text(t) => t,
                            Message::Close(_) => break,
                            // Pong frames are keepalive responses; Ping frames are
                            // answered automatically by axum's WS. Drop both.
                            Message::Ping(_) | Message::Pong(_) => continue,
                            Message::Binary(_) => continue, // ignore binary
                        };

                        // Parse as JSON to check for relay control frames.
                        let frame: serde_json::Value = match serde_json::from_str(&text) {
                            Ok(v) => v,
                            Err(e) => {
                                warn!(peer = %peer_short, err = %e, "invalid json, dropping");
                                continue;
                            }
                        };

                        // Frames with a top-level "type" are handled by the relay itself.
                        if let Some(t) = frame.get("type").and_then(|v| v.as_str()) {
                            match t {
                                // ── presence control frames (plano 12) ──
                                "subscribe_presence" => {
                                    let Some(peers) =
                                        parse_bounded_control_peers(&frame, t, &peer_short)
                                    else {
                                        continue;
                                    };
                                    presence.subscribe(peer_id.clone(), peers.clone()).await;
                                    // Backfill: push peer_online for any already-online
                                    // peers in the list, so subscribers don't have to
                                    // call presence_check to discover current state.
                                    registry.backfill_presence(&peer_id, &peers);
                                }
                                "unsubscribe_presence" => {
                                    let peers = parse_bounded_control_peers(&frame, t, &peer_short)
                                        .unwrap_or_default();
                                    presence.unsubscribe(&peer_id, peers).await;
                                }
                                "presence_check" => {
                                    let Some(peers) =
                                        parse_bounded_control_peers(&frame, t, &peer_short)
                                    else {
                                        continue;
                                    };
                                    let cost = control_check_cost(&peers);
                                    if !control_check_limiter.allow(cost) {
                                        warn!(
                                            peer = %peer_short,
                                            frame_type = %t,
                                            cost,
                                            limit = MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW,
                                            window_secs = CONTROL_CHECK_PEER_COST_WINDOW.as_secs(),
                                            "control frame check rate limit exceeded, dropping"
                                        );
                                        continue;
                                    }
                                    let states = presence
                                        .snapshot(&peers, |p| registry.is_online(p))
                                        .await;
                                    let resp = serde_json::json!({
                                        "type": "presence",
                                        "states": states,
                                    })
                                    .to_string();
                                    // Dedup: skip reply if identical to the
                                    // previous one we sent on this conn. The
                                    // first reply always goes through (cache
                                    // is None until the first emit).
                                    if last_presence_resp.as_deref() == Some(resp.as_str()) {
                                        metrics.inc_presence_suppressed(1);
                                    } else {
                                        last_presence_resp = Some(resp.clone());
                                        if sink.send(Message::Text(resp)).await.is_err() {
                                            break;
                                        }
                                        metrics.inc_presence_emitted(1);
                                    }
                                }

                                // ── rooms control frames (plano 17) ──
                                "subscribe_rooms" => {
                                    let Some(peers) =
                                        parse_bounded_control_peers(&frame, t, &peer_short)
                                    else {
                                        continue;
                                    };
                                    rooms.subscribe(peer_id.clone(), peers).await;
                                }
                                "unsubscribe_rooms" => {
                                    let peers = parse_bounded_control_peers(&frame, t, &peer_short)
                                        .unwrap_or_default();
                                    rooms.unsubscribe(&peer_id, peers).await;
                                }
                                "rooms_check" => {
                                    let Some(peers) =
                                        parse_bounded_control_peers(&frame, t, &peer_short)
                                    else {
                                        continue;
                                    };
                                    let cost = control_check_cost(&peers);
                                    if !control_check_limiter.allow(cost) {
                                        warn!(
                                            peer = %peer_short,
                                            frame_type = %t,
                                            cost,
                                            limit = MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW,
                                            window_secs = CONTROL_CHECK_PEER_COST_WINDOW.as_secs(),
                                            "control frame check rate limit exceeded, dropping"
                                        );
                                        continue;
                                    }
                                    for target_peer in &peers {
                                        let active_rooms = registry.rooms_of(target_peer);
                                        let resp = serde_json::json!({
                                            "type": "rooms",
                                            "peer": target_peer,
                                            "rooms": active_rooms,
                                        })
                                        .to_string();
                                        // Dedup per (conn, target_peer):
                                        // first reply always sent; subsequent
                                        // identical snapshots dropped.
                                        if last_rooms_resp.get(target_peer) == Some(&resp) {
                                            metrics.inc_rooms_suppressed(1);
                                            continue;
                                        }
                                        last_rooms_resp.insert(target_peer.clone(), resp.clone());
                                        if sink.send(Message::Text(resp)).await.is_err() {
                                            break 'routing;
                                        }
                                        metrics.inc_rooms_emitted(1);
                                    }
                                }

                                // ── room meta update (plano 18 + 28 + 32) ──
                                // `meta.model`, `meta.thinking` and
                                // `meta.working` are patched independently: a
                                // field absent from `meta` is *left alone* on
                                // the room (not cleared). For the nullable
                                // string fields, an explicit `null` clears
                                // them. `working` is a plain bool, so it only
                                // ever toggles — a non-bool/absent value leaves
                                // it untouched. Mirrors the JSON Merge Patch
                                // shape clients already produce.
                                "room_meta_update" => {
                                    let target_room = frame
                                        .get("room_id")
                                        .and_then(|v| v.as_str())
                                        .unwrap_or(&room_id)
                                        .to_string();
                                    let meta_obj = frame
                                        .get("meta")
                                        .and_then(|v| v.as_object());
                                    let model_patch = meta_obj
                                        .and_then(|m| m.get("model"))
                                        .map(|v| v.as_str().map(String::from));
                                    let thinking_patch = meta_obj
                                        .and_then(|m| m.get("thinking"))
                                        .map(|v| v.as_str().map(String::from));
                                    let session_id_patch = meta_obj
                                        .and_then(|m| m.get("session_id"))
                                        .map(|v| v.as_str().map(String::from));
                                    let working_patch = meta_obj
                                        .and_then(|m| m.get("working"))
                                        .and_then(|v| v.as_bool());
                                    let patch = RoomMetaPatch {
                                        model: model_patch,
                                        thinking: thinking_patch,
                                        session_id: session_id_patch,
                                        working: working_patch,
                                    };
                                    if !registry
                                        .update_room_meta(&peer_id, &target_room, patch)
                                        .await
                                    {
                                        warn!(
                                            peer = %peer_short,
                                            room = %target_room,
                                            "room_meta_update for unknown (peer, room), dropping"
                                        );
                                    }
                                }

                                // ── Pi-to-Pi envelope forward (plano 25 W-A) ──
                                "pi_envelope" => {
                                    use crate::handlers::pi_forward::{
                                        PiForwardResult, handle_pi_envelope,
                                    };
                                    match handle_pi_envelope(
                                        &peer_id,
                                        &frame,
                                        &registry,
                                        &mesh,
                                        &mesh_auth,
                                    )
                                    .await
                                    {
                                        PiForwardResult::Forwarded => {}
                                        PiForwardResult::TransportError(err_msg) => {
                                            if sink.send(err_msg).await.is_err() {
                                                break;
                                            }
                                        }
                                    }
                                }

                                _ => {
                                    warn!(
                                        peer = %peer_short,
                                        frame_type = %t,
                                        "unknown control frame type, dropping"
                                    );
                                }
                            }
                            continue; // do not fall through to envelope path
                        }

                        // No "type" field → outer envelope (opaque routing).
                        match parse_line(&text) {
                            Err(e) => {
                                warn!(peer = %peer_short, err = %e, "invalid envelope, dropping");
                            }
                            Ok(env) => {
                                let ct_len = env.ct.len();
                                let dest_peer = env.peer;
                                let dest_room = env.room;
                                let dest_tail =
                                    dest_peer[dest_peer.len().saturating_sub(8)..].to_string();
                                // Rewrite: recipient sees sender's peer_id + sender's room_id.
                                let rewritten = OuterEnvelope {
                                    peer: peer_id.clone(),
                                    room: room_id.clone(),
                                    ct: env.ct,
                                };
                                let fwd_line = serde_json::to_string(&rewritten)
                                    .expect("OuterEnvelope serialisation is infallible");
                                // Skip-sender: pass our own conn_id so multi-device
                                // Owners don't echo their own outbound messages.
                                if !registry.forward(
                                    &dest_peer,
                                    &dest_room,
                                    Message::Text(fwd_line),
                                    conn_id,
                                ) {
                                    warn!(
                                        from = %peer_short,
                                        dest = %dest_tail,
                                        room = %dest_room,
                                        bytes = ct_len,
                                        "dest (peer, room) not found, dropping",
                                    );
                                }
                            }
                        }
                    }
                }
            }
            result = rx.recv() => {
                match result {
                    Some(msg) => {
                        if sink.send(msg).await.is_err() {
                            break;
                        }
                    }
                    None => break,
                }
            }
            _ = heartbeat.tick() => {
                if sink.send(Message::Ping(Vec::new())).await.is_err() {
                    break;
                }
            }
        }
    }

    registry.unregister(&peer_id, &room_id, conn_id).await;
    rooms.unsubscribe_all(&peer_id).await;
    info!(peer = %peer_short, room = %room_id, addr = %peer_addr, "disconnected");
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
