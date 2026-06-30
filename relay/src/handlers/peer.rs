use std::net::SocketAddr;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{ConnectInfo, State};
use axum::response::Response;
use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio::time::{self, Duration};
use tracing::{info, warn};

use crate::AppState;
use crate::auth::challenge::{
    HELLO_TIMEOUT_MS, challenge_line, gen_nonce, parse_hello_bootstrap, verify_auth,
};
#[path = "connection_actor.rs"]
pub(crate) mod connection_actor;

use crate::handlers::control::is_presence_rooms_control_frame;
use crate::handlers::peer::connection_actor::{ActorDispatch, ConnectionActor};
use crate::protocol::generated::control::RelayControlFrame;
use crate::protocol::outer::{OuterEnvelope, parse_line};
use crate::reachability::RELAY_WS_PING_INTERVAL;
use crate::rooms::RoomMetaPatch;

/// Maximum number of peer IDs accepted in one presence/rooms control frame.
/// The relay uses unbounded per-connection channels internally, so every frame
/// that can register subscriptions or request per-peer snapshots must have a
/// small, explicit fanout ceiling.
pub const MAX_CONTROL_FRAME_PEERS: usize = 64;

/// Maximum peer-cost a single WebSocket connection may spend on presence/rooms
/// check frames inside one limiter window. Empty checks still cost 1 so a peer
/// cannot spin free no-op requests indefinitely.
pub const MAX_CONTROL_CHECK_PEER_COST_PER_WINDOW: usize = MAX_CONTROL_FRAME_PEERS * 4;
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

    let started_at = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64;
    let authenticated = match parse_hello_bootstrap(&hello_text, started_at) {
        Ok(peer) => peer,
        Err(e) => {
            warn!(addr = %peer_addr, err = %e, "bad hello, closing");
            return;
        }
    };
    let vk = authenticated.verifying_key;

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

    let peer_id = authenticated.peer_id;
    let peer_short = peer_id[peer_id.len().saturating_sub(8)..].to_string();
    let room_meta = authenticated.room_meta;
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

    let mut actor = ConnectionActor::new(
        peer_id.clone(),
        peer_short.clone(),
        registry.clone(),
        presence,
        rooms.clone(),
        metrics,
    );

    // ── 4. Routing loop ───────────────────────────────────────────────────
    // Send a WS Ping every 25 s so NAT/LB idle timers don't close the connection.
    // First tick fires after 25 s (not immediately).
    let mut heartbeat = time::interval_at(
        time::Instant::now() + RELAY_WS_PING_INTERVAL,
        RELAY_WS_PING_INTERVAL,
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
                        if let Some(t) = frame
                            .get("type")
                            .and_then(|v| v.as_str())
                            .map(str::to_owned)
                        {
                            if is_presence_rooms_control_frame(&t) {
                                let control_frame = match serde_json::from_value::<RelayControlFrame>(frame) {
                                    Ok(frame) => frame,
                                    Err(err) => {
                                        warn!(
                                            peer = %peer_short,
                                            frame_type = %t,
                                            err = %err,
                                            "malformed typed control frame, dropping"
                                        );
                                        continue;
                                    }
                                };

                                match actor.dispatch_control(control_frame).await {
                                    ActorDispatch::Continue => {}
                                    ActorDispatch::Send(msg) => {
                                        if sink.send(msg).await.is_err() {
                                            break;
                                        }
                                    }
                                    ActorDispatch::SendMany(messages) => {
                                        for msg in messages {
                                            if sink.send(msg).await.is_err() {
                                                break 'routing;
                                            }
                                        }
                                    }
                                }
                                continue;
                            }

                            match t.as_str() {
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
                                    let working_patch = meta_obj
                                        .and_then(|m| m.get("working"))
                                        .and_then(|v| v.as_bool());
                                    let patch = RoomMetaPatch {
                                        model: model_patch,
                                        thinking: thinking_patch,
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
