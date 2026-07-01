//! Plan 25 Wave A — integration tests for Pi-to-Pi envelope forwarding.
//!
//! Each test spins up the full unified relay (WS + HTTP), publishes one or
//! more Owner-signed mesh blobs that determine membership, connects Pi-A
//! (and sometimes Pi-B) via WebSocket, and asserts the forwarding /
//! transport-error behavior.
//!
//! Cross-PC `pi_envelope` carries `to_room`: the relay routes the frame only
//! to the addressed room of the destination peer (room-targeted delivery,
//! not peer-wide fanout), and the delivered `pi_envelope_in` echoes `to_room`.

mod common;
use common::{connect_and_auth_with_key, connect_and_auth_with_room, start_relay};

use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::{Signer, SigningKey};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use tokio_tungstenite::tungstenite::Message;

fn random_key() -> SigningKey {
    SigningKey::generate(&mut rand::thread_rng())
}

fn pk_hash_hex(pk: &[u8]) -> String {
    let d = Sha256::digest(pk);
    let mut s = String::with_capacity(64);
    for b in d {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn is_uuid_like(value: &str) -> bool {
    value.len() == 36
        && value.chars().enumerate().all(|(idx, ch)| match idx {
            8 | 13 | 18 | 23 => ch == '-',
            _ => ch.is_ascii_hexdigit(),
        })
}

/// Asserts `frame` is a relay `_relay` transport-error `pi_envelope_in`.
/// `to_room` defaults to `"main"` — the sender's room (errors are sent back to
/// the sender on their own socket, so `to_room` is the sender's room).
fn assert_transport_error(frame: &Value, reason: &str, re: Option<&str>) {
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(frame["from_pc"], "_relay");
    assert_eq!(frame["envelope"]["body"]["type"], "transport_error");
    assert_eq!(frame["envelope"]["body"]["reason"], reason);
    assert!(
        is_uuid_like(frame["envelope"]["id"].as_str().unwrap_or_default()),
        "relay-synthesized transport_error id must be UUID-shaped"
    );
    match re {
        Some(expected) => assert_eq!(frame["envelope"]["re"], expected),
        None => assert!(
            frame["envelope"]["re"].is_null(),
            "re must be null when original id is unrecoverable"
        ),
    }
}

/// Publishes an Owner-signed `mesh_versions` blob via the relay's HTTP API.
/// `members` is the list of Pi-pubkeys (base64 strings) that this Owner
/// authorizes as siblings.
async fn publish_owner_blob(
    base_http: &str,
    owner_sk: &SigningKey,
    members: &[&str],
    version: u64,
) {
    let owner_pk_bytes = owner_sk.verifying_key().to_bytes();
    let owner_pk_b64 = B64.encode(owner_pk_bytes);
    let members_json: Vec<Value> = members.iter().map(|m| json!({ "remote_epk": m })).collect();
    let blob = json!({
        "owner_pk": owner_pk_b64,
        "version": version,
        "members": members_json,
        "issued_at": 1700000000000_u64,
    });
    let blob_bytes = serde_json::to_vec(&blob).unwrap();
    let sig = owner_sk.sign(&blob_bytes);
    let envelope = json!({
        "blob": B64.encode(&blob_bytes),
        "sig": B64.encode(sig.to_bytes()),
    });
    let hash = pk_hash_hex(&owner_pk_bytes);
    let client = reqwest::Client::new();
    let r = client
        .post(format!("{base_http}/mesh/{hash}"))
        .json(&envelope)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), 200, "mesh blob publish must succeed");
}

/// Sends a `pi_envelope` frame from an already-authenticated Pi WS, addressed
/// to `to_pc` / `to_room`.
async fn send_pi_envelope(ws: &mut common::WsStream, to_pc: &str, to_room: &str, envelope: Value) {
    ws.send(Message::text(
        json!({
            "type": "pi_envelope",
            "to_pc": to_pc,
            "to_room": to_room,
            "envelope": envelope,
        })
        .to_string(),
    ))
    .await
    .unwrap();
}

/// Receives the next text frame (with timeout) and parses as JSON.
async fn recv_json(ws: &mut common::WsStream, label: &str) -> Value {
    let msg = tokio::time::timeout(tokio::time::Duration::from_secs(2), ws.next())
        .await
        .unwrap_or_else(|_| panic!("{label} timed out waiting for frame"))
        .unwrap()
        .unwrap();
    serde_json::from_str(msg.to_text().unwrap())
        .unwrap_or_else(|e| panic!("{label} got non-JSON frame: {e}"))
}

/// Asserts that no frame arrives on `ws` within `ms` (used to prove a room was
/// NOT targeted by room-targeted delivery).
async fn assert_no_frame(ws: &mut common::WsStream, label: &str, ms: u64) {
    let got = tokio::time::timeout(tokio::time::Duration::from_millis(ms), ws.next()).await;
    assert!(
        got.is_err(),
        "{label}: expected no frame (room not targeted), got one"
    );
}

// ────────────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────────────

/// Happy path: Pi-A and Pi-B belong to the same Owner's mesh and both are
/// online in room "main". Envelope from A arrives at B verbatim, wrapped as
/// `pi_envelope_in` with `from_pc = peer_a_pk` and `to_room = "main"`.
#[tokio::test]
async fn happy_path_same_owner_envelope_delivered_verbatim() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;

    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": "u1",
        "re": null,
        "body": { "type": "hello", "text": "ping", "session_id": "opaque-session" },
    });
    let t0 = std::time::Instant::now();
    send_pi_envelope(&mut ws_a, &peer_b, "main", envelope.clone()).await;

    let frame = recv_json(&mut ws_b, "ws_b").await;
    let latency = t0.elapsed();
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(
        frame["from_pc"], peer_a,
        "must carry authenticated sender pk"
    );
    assert_eq!(
        frame["to_room"], "main",
        "delivered pi_envelope_in echoes the addressed to_room"
    );
    assert_eq!(
        frame["envelope"], envelope,
        "envelope must be forwarded verbatim, including opaque session_id in body"
    );
    assert!(
        latency < std::time::Duration::from_millis(100),
        "loopback latency {latency:?} should be well under 100ms"
    );
}

/// Session identity inside the generic envelope body is endpoint-owned data.
/// Relay forwarding targets only the wrapper's `to_pc`/`to_room` and carries the
/// envelope JSON through unchanged.
#[tokio::test]
async fn session_id_in_body_is_opaque_and_forwarded_verbatim() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;

    let envelope = json!({
        "from": "casa:local-session",
        "to": "trab:agent-1",
        "id": "opaque-session-id-body",
        "re": "previous-turn",
        "body": {
            "type": "hello",
            "session_id": "not-a-relay-room-and-not-a-routing-key",
            "nested": {
                "session_id": "also-opaque",
                "to_room": "ignored-body-room"
            },
            "items": [
                { "session_id": "array-value-preserved" },
                "plain-value"
            ]
        },
    });
    send_pi_envelope(&mut ws_a, &peer_b, "main", envelope.clone()).await;

    let frame = recv_json(&mut ws_b, "ws_b opaque-session forward").await;
    let wrapper = frame
        .as_object()
        .expect("forwarded frame must be a JSON object");
    assert_eq!(
        wrapper.len(),
        4,
        "relay wrapper should only add owned fields (type, from_pc, to_room, envelope)"
    );
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(frame["from_pc"], peer_a);
    assert_eq!(frame["to_room"], "main");
    assert_eq!(
        frame["envelope"], envelope,
        "relay must carry the generic envelope as opaque JSON, including body.session_id"
    );
}

/// Room-targeted delivery: Pi-B is live in TWO rooms ("main" and "work"). A
/// frame addressed `to_room: "work"` reaches ONLY the "work" connection, not
/// "main". (Replaces the legacy peer-wide fanout behavior.)
#[tokio::test]
async fn room_targeted_forward_reaches_only_addressed_room() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut ws_b_main, _) = connect_and_auth_with_room(port, &sk_b, "main").await;
    let (mut ws_b_work, _) = connect_and_auth_with_room(port, &sk_b, "work").await;

    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": "room-targeted-forward",
        "re": null,
        "body": { "type": "ping", "session_id": "opaque-session" },
    });
    send_pi_envelope(&mut ws_a, &peer_b, "work", envelope.clone()).await;

    // Only the "work" connection receives the frame.
    let frame = recv_json(&mut ws_b_work, "ws_b_work").await;
    assert_eq!(frame["type"], "pi_envelope_in");
    assert_eq!(frame["from_pc"], peer_a);
    assert_eq!(frame["to_room"], "work");
    assert_eq!(frame["envelope"], envelope);

    // The "main" connection must NOT receive it (room-targeted, not peer-wide).
    assert_no_frame(&mut ws_b_main, "ws_b_main (not targeted)", 150).await;
}

/// B is offline entirely (no connection). A's frame to `to_room: "main"`
/// returns `transport_error: offline` correlated to the original id.
#[tokio::test]
async fn pi_b_offline_returns_transport_error_offline() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    // Only A connects — B is offline.
    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;

    let original_id = "018f1111-1111-7111-8111-111111111111";
    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": original_id,
        "re": null,
        "body": { "type": "ping" },
    });
    send_pi_envelope(&mut ws_a, &peer_b, "main", envelope).await;

    let frame = recv_json(&mut ws_a, "ws_a transport_error").await;
    assert_transport_error(&frame, "offline", Some(original_id));
    assert_eq!(frame["envelope"]["from"], "_relay");
    assert_eq!(frame["envelope"]["to"], "casa:sess-3");
}

/// Unknown destination ROOM: B is online in "main", but A targets `to_room:
/// "work"` (which B is not in). A receives `transport_error: offline`
/// correlated to the original id. (Room-targeted: a peer online in a
/// different room is effectively offline for this `to_room`.)
#[tokio::test]
async fn unknown_destination_room_returns_offline() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    // B is online, but only in "main" — not "work".
    let (_ws_b_main, _) = connect_and_auth_with_room(port, &sk_b, "main").await;

    let original_id = "018f3333-3333-7333-8333-333333333333";
    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": original_id,
        "re": null,
        "body": { "type": "ping" },
    });
    send_pi_envelope(&mut ws_a, &peer_b, "work", envelope).await;

    let frame = recv_json(&mut ws_a, "ws_a transport_error (unknown room)").await;
    assert_transport_error(&frame, "offline", Some(original_id));
}

/// Pi-A and Pi-B belong to DIFFERENT Owners. The relay's mesh authorization
/// rejects the forward; A gets `transport_error: not_authorized`.
#[tokio::test]
async fn cross_owner_returns_transport_error_not_authorized() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner_1 = random_key();
    let owner_2 = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());

    // Two separate Owners, each with just one Pi in their mesh.
    publish_owner_blob(&base_http, &owner_1, &[&peer_a], 1).await;
    publish_owner_blob(&base_http, &owner_2, &[&peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut _ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;

    let original_id = "018f2222-2222-7222-8222-222222222222";
    let envelope = json!({
        "from": "casa:sess-3",
        "to": "trab:agent-1",
        "id": original_id,
        "re": null,
        "body": { "type": "ping" },
    });
    send_pi_envelope(&mut ws_a, &peer_b, "main", envelope).await;

    let frame = recv_json(&mut ws_a, "ws_a transport_error").await;
    assert_transport_error(&frame, "not_authorized", Some(original_id));
}

/// Malformed `pi_envelope` (missing `to_pc` / `envelope`): relay returns
/// `transport_error: bad_envelope` to A. The error envelope's `re` is null
/// because we can't recover the original id.
#[tokio::test]
async fn malformed_pi_envelope_returns_transport_error_bad_envelope() {
    let port = start_relay().await;

    let sk_a = random_key();
    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;

    // No `to_pc`, no `to_room`, no `envelope` — pure stub.
    ws_a.send(Message::text(json!({ "type": "pi_envelope" }).to_string()))
        .await
        .unwrap();

    let frame = recv_json(&mut ws_a, "ws_a bad_envelope").await;
    assert_transport_error(&frame, "bad_envelope", None);
}

/// A `pi_envelope` with a valid `to_pc` but MISSING `to_room` returns
/// `transport_error: bad_envelope` — the relay requires `to_room` for
/// room-targeted routing. (Was `no_to_room_reaches_authorization` under the
/// legacy peer-wide contract; the AC now mandates bad_envelope, not auth.)
#[tokio::test]
async fn missing_to_room_returns_bad_envelope() {
    let port = start_relay().await;

    let sk_a = random_key();
    let sk_b = random_key();
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());
    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;

    let original_id = "018f5555-5555-7555-8555-555555555555";
    ws_a.send(Message::text(
        json!({
            "type": "pi_envelope",
            "to_pc": peer_b,
            // deliberately no to_room
            "envelope": {
                "from": "casa:sess-3",
                "to": "trab:agent-1",
                "id": original_id,
                "re": null,
                "body": { "type": "ping", "session_id": "opaque-session" },
            },
        })
        .to_string(),
    ))
    .await
    .unwrap();

    let frame = recv_json(&mut ws_a, "ws_a missing-to-room bad_envelope").await;
    assert_transport_error(&frame, "bad_envelope", Some(original_id));
    assert_eq!(frame["envelope"]["to"], "casa:sess-3");
}

/// Cache behavior: after a successful authorization lookup, subsequent
/// envelopes between the same two Pis don't require re-scanning SQLite.
/// We can't easily count SQL hits at this layer, but we can verify that
/// repeated forwards in quick succession all succeed without observable
/// regression.
#[tokio::test]
async fn cache_warm_subsequent_envelopes_still_delivered() {
    let port = start_relay().await;
    let base_http = format!("http://127.0.0.1:{port}");

    let owner = random_key();
    let sk_a = random_key();
    let sk_b = random_key();
    let peer_a = B64.encode(sk_a.verifying_key().to_bytes());
    let peer_b = B64.encode(sk_b.verifying_key().to_bytes());
    publish_owner_blob(&base_http, &owner, &[&peer_a, &peer_b], 1).await;

    let (mut ws_a, _) = connect_and_auth_with_key(port, &sk_a).await;
    let (mut ws_b, _) = connect_and_auth_with_key(port, &sk_b).await;

    for i in 0..5 {
        let env = json!({
            "from": "casa:s",
            "to": "trab:a",
            "id": format!("u{i}"),
            "re": null,
            "body": { "type": "ping", "seq": i },
        });
        send_pi_envelope(&mut ws_a, &peer_b, "main", env.clone()).await;
        let frame = recv_json(&mut ws_b, &format!("ws_b iter {i}")).await;
        assert_eq!(frame["envelope"]["id"], format!("u{i}"));
        assert_eq!(frame["envelope"]["body"]["seq"], i);
    }
}
