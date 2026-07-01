use base64::{Engine as _, engine::general_purpose::STANDARD as B64};
use ed25519_dalek::{Signer as _, SigningKey};

use super::challenge::{AuthError, RELAY_AUTH_DOMAIN_PREFIX, gen_nonce, parse_hello, parse_hello_bootstrap, verify_auth};

/// First message is not "hello" → NoHello error.
#[test]
fn sem_hello() {
    // Send an "auth" message before any hello
    let line = r#"{"type":"auth","sig":"AAAA"}"#;
    let err = parse_hello(line).unwrap_err();
    assert!(matches!(err, AuthError::NoHello));
}

#[test]
fn hello_bootstrap_defaults_and_room_meta() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = format!(
        r#"{{"type":"hello","pubkey":"{}","room_id":"work","room_meta":{{"name":"Desk","cwd":"/repo","session_id":"sess-1","model":"m","thinking":"high","working":true}}}}"#,
        pubkey
    );

    let peer = parse_hello_bootstrap(&line, 1234).unwrap();
    assert_eq!(peer.peer_id, pubkey);
    assert_eq!(peer.room_meta.room_id, "work");
    assert_eq!(peer.room_meta.name.as_deref(), Some("Desk"));
    assert_eq!(peer.room_meta.cwd.as_deref(), Some("/repo"));
    assert_eq!(peer.room_meta.session_id.as_deref(), Some("sess-1"));
    assert_eq!(peer.room_meta.model.as_deref(), Some("m"));
    assert_eq!(peer.room_meta.thinking.as_deref(), Some("high"));
    assert!(peer.room_meta.working);
    assert_eq!(peer.room_meta.started_at, 1234);
}

#[test]
fn hello_bootstrap_defaults_main_and_not_working() {
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let pubkey = B64.encode(sk.verifying_key().to_bytes());
    let line = format!(r#"{{"type":"hello","pubkey":"{}"}}"#, pubkey);

    let peer = parse_hello_bootstrap(&line, 77).unwrap();
    assert_eq!(peer.room_meta.room_id, "main");
    assert!(!peer.room_meta.working);
    assert_eq!(peer.room_meta.started_at, 77);
}

/// Valid key pair but signature covers wrong bytes → InvalidSig.
#[test]
fn sig_invalida() {
    let (nonce, _) = gen_nonce();
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    // Sign something other than the domain-separated nonce
    let wrong_sig = sk.sign(b"not the nonce");
    let sig_b64 = B64.encode(wrong_sig.to_bytes());
    let line = format!(r#"{{"type":"auth","sig":"{}"}}"#, sig_b64);

    let err = verify_auth(&nonce, &vk, &line).unwrap_err();
    assert!(matches!(err, AuthError::InvalidSig));
}

/// Valid key pair, signature covers the correct nonce bytes → success.
#[test]
fn sig_valida() {
    let (nonce, _) = gen_nonce();
    let sk = SigningKey::generate(&mut rand::thread_rng());
    let vk = sk.verifying_key();

    // Sign the domain-separated nonce (prefix ++ nonce) — matches verify_auth.
    let mut signed = Vec::with_capacity(RELAY_AUTH_DOMAIN_PREFIX.len() + nonce.len());
    signed.extend_from_slice(RELAY_AUTH_DOMAIN_PREFIX);
    signed.extend_from_slice(&nonce);
    let sig = sk.sign(&signed);
    let sig_b64 = B64.encode(sig.to_bytes());
    let line = format!(r#"{{"type":"auth","sig":"{}"}}"#, sig_b64);

    verify_auth(&nonce, &vk, &line).unwrap();
}
