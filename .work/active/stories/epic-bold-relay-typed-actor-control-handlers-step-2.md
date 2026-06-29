---
id: epic-bold-relay-typed-actor-control-handlers-step-2
kind: story
stage: implementing
tags: [refactor, bold, relay]
parent: epic-bold-relay-typed-actor-control-handlers
depends_on: [epic-bold-relay-typed-actor-control-handlers-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Type the auth challenge and hello room bootstrap handler

**Priority**: High  
**Risk**: Medium  
**Source Lens**: fail-fast boundary / generated contracts  
**Files**: `relay/src/auth/challenge.rs`, `relay/src/handlers/peer.rs`, `relay/src/handlers/connection_actor.rs`, generated auth/hello room metadata types, `relay/src/rooms.rs`

## Current State

The auth helpers parse only the `pubkey`/`sig` shape, then `handle_peer` reparses the original hello as raw JSON to recover `room_id` and `room_meta`:

```rust
let vk = parse_hello(&hello_text)?;
/* challenge + verify_auth */
let room_meta = {
    let hello: serde_json::Value = serde_json::from_str(&hello_text).unwrap_or(serde_json::Value::Null);
    let room_id = hello.get("room_id").and_then(|v| v.as_str()).unwrap_or("main").to_string();
    let room_meta_val = hello.get("room_meta");
    let working = room_meta_val
        .and_then(|m| m.get("working"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    RoomMeta { room_id, /* raw field peel */ working, started_at }
};
```

This makes auth a partial typed boundary and duplicates hello parsing outside the auth handler.

## Target State

Make auth return one authenticated bootstrap value with typed hello metadata:

```rust
pub struct AuthenticatedPeer {
    pub verifying_key: VerifyingKey,
    pub peer_id: String,
    pub room_meta: RoomMeta,
}

pub async fn authenticate_peer(
    stream: &mut PeerStream,
    sink: &mut PeerSink,
    clock: impl Clock,
) -> Result<AuthenticatedPeer, AuthError> {
    let hello: ClientHello = read_typed_hello(stream).await?;
    let vk = verifying_key_from_pubkey(&hello.pubkey)?;
    let (nonce, nonce_b64) = gen_nonce();
    send_challenge(sink, &nonce_b64).await?;
    verify_typed_auth(stream, &vk, &nonce).await?;
    Ok(AuthenticatedPeer {
        peer_id: B64.encode(vk.to_bytes()),
        verifying_key: vk,
        room_meta: hello.into_room_meta(clock.now_ms()),
    })
}
```

`handle_peer` receives `AuthenticatedPeer` and no longer reparses `hello_text`.

## Implementation Notes

- Consume generated auth and hello-room metadata structs from the Rust protocol codegen; do not create a second handwritten hello mirror.
- Preserve wire defaults: `room_id` defaults to `main`, missing `room_meta.working` defaults to `false`, and optional metadata fields remain optional.
- Auth still owns nonce generation and Ed25519 verification. Generation owns only JSON frame shape.
- Keep logs content-free: peer tail, address, and coarse auth reason only; never log signatures or full hello payloads.

## Acceptance Criteria

- [ ] `handle_peer` does not reparse `hello_text` as `serde_json::Value` after auth.
- [ ] Typed hello parsing yields `RoomMeta` with the same default-room and `working: false` behavior.
- [ ] Auth challenge and signature verification behavior remains unchanged.
- [ ] Malformed hello/auth frames fail before registry registration.
- [ ] Relay fmt/clippy/tests pass.

## Risk

Medium. The auth path is connection-critical; default handling for existing clients must remain compatible.

## Rollback

Restore `parse_hello`/`verify_auth` plus the current raw hello `room_meta` extraction in `handle_peer`. This rollback is isolated from the post-auth control-handler stories.
