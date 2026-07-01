---
id: epic-bold-canonical-session-relay-opaque-targeting
kind: feature
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-identity-model]
release_binding: relay-0.2.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — relay opaque session targeting

## Brief
The relay forwards to `(to_pc, to_room)` and carries `session_id` opaquely —
it doesn't understand session semantics, just targets them. Retires
`forward_to_peer` fanout (`relay/src/peers/registry.rs:369-384`), which today
sends a cross-PC `pi_envelope` to **every** live room on the destination PC.
Absorbs the relay half of `relay-cross-pc-room-targeting`. The receiving
pi-extension broker validates the incoming `pi_envelope_in` targets a local
session/room that exists before injecting (fail-closed drop + log), alongside
the existing anti-spoof `from_pc` prefix check.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: the relay half of the contamination fix. Depends on the identity
  model pinning the relay's opaque posture.

## Foundation references
- Evidence: `relay/src/handlers/pi_forward.rs:128-173`,
  `relay/src/peers/registry.rs:369-384`, `relay/src/handlers/peer.rs:440-484`
  (normal app↔Pi outer envelopes ARE already room-targeted — the cross-PC path
  is the outlier).

<!-- /agile-workflow:refactor-design pins `to_room` on pi_envelope + the
forward path. -->

## Design decisions

- **Relay session posture**: inherited from `epic-bold-canonical-session-identity-model`: the relay never learns sessions. App↔Pi `session_id` lives inside opaque `ct`; Pi↔Pi `session_id` may live inside the generic envelope body; relay-owned routing keys remain `(peer, room)` and `(to_pc, to_room)`.
- **Cross-PC target shape**: `pi_envelope` gains relay-owned `to_room`; `pi_envelope_in` carries the same `to_room` to make the receiver-side fail-closed room/session guard explicit. `to_room` is a relay room key, not a session id.
- **Fanout retirement**: cross-PC delivery must use the same room-targeted registry path as app↔Pi outer envelopes. `forward_to_peer` is removed from the `pi_envelope` path and should not remain as a public general-purpose escape hatch.
- **Missing target behavior**: in the clean-room path, missing or empty `to_room` is a `bad_envelope` transport error. If an implementation needs a short compatibility seam, it must be isolated, test-covered, and marked removable; it must not silently fan out as the long-term behavior.
- **Transport errors**: keep `_relay` `transport_error` envelopes with `bad_envelope`, `not_authorized`, and `offline`, correlated via `re`. Unknown destination room returns `offline` because the addressed target is not live.
- **Generated/typed-actor coordination**: until generated Rust frame types land, implement on the current raw JSON boundary in `relay/src/handlers/pi_forward.rs`; when `epic-bold-generated-protocol-rust-codegen` and `epic-bold-relay-typed-actor-frame-dispatch` land, their generated `PiEnvelopeFrame` and actor dispatch must include `to_room` and keep body opacity.
- **Refactor-tag rationale**: this changes the observable cross-PC fanout behavior, but remains in the bold `[refactor]` lane by explicit autopilot/operator direction because it restores the canonical-session invariant in a fork-private clean-room break. The behavior change is made explicit and verified with fail-closed tests rather than preserving legacy fanout.
- **Patchbay posture**: targeting is expressed as a neutral room-addressed relay envelope, not by embedding Remote Pi session semantics in relay storage. Patchbay can later replace the endpoint session issuer or broker without unwinding relay-owned `session_id` logic.
- **Dispatch rationale**: direct-read design only. The target was a bounded relay slice with explicit grounding files; no exploratory sub-agent was needed. The harness task delegated this worker specifically for refactor-design, and raised-tier sub-delegation was unnecessary for the small relay scope.
- **Cycle check**: `.work/bin/work-view --blocking` is absent in this checkout, so the mandatory tool check could not run. Manual frontmatter check found no back-edge: step 1 depends on landed prerequisite `epic-bold-canonical-session-identity-model`; steps 2-4 depend only on the immediately previous story; no existing item depends on these new stories.

## Code-smell scan findings

1. **Code smell — cross-PC peer-wide fanout**: `PeerRegistry::forward_to_peer` sends a `pi_envelope` to every live room for a destination peer, unlike normal app↔Pi `OuterEnvelope` routing through `(peer, room)`. High value: removes the relay-side vector for cross-session contamination.
2. **Missing abstraction — no typed cross-PC target**: `handle_pi_envelope` extracts only `to_pc` and an opaque `envelope`, so the relay has no way to express the room target it already understands elsewhere. High value: makes cross-PC targeting explicit and generated-protocol-ready.
3. **Pattern drift — app↔Pi and Pi↔Pi routing differ**: app↔Pi rewrites and forwards by destination `(peer, room)`, while Pi↔Pi authorizes by peer and fans out. High value: unifies relay routing on one room-targeted path.
4. **Dead weight — public fanout helper after targeting lands**: once cross-PC uses `(to_pc, to_room)`, `forward_to_peer` is a hazardous public escape hatch. Medium value: deleting or hiding it prevents future call sites from reintroducing peer-wide delivery.
5. **No project-specific refactor convention catalog**: `.agents/skills/refactor-conventions/` is absent; no convention-driven step was added beyond the default refactor-design lenses.

## Refactor Overview

The relay already has the right primitive for app↔Pi traffic: `PeerRegistry::forward(dest_peer, dest_room, msg, from_conn_id)` targets one `(peer, room)` and does not inspect content. Cross-PC forwarding is the outlier: `handle_pi_envelope` authorizes `to_pc`, wraps a `pi_envelope_in`, and calls `forward_to_peer`, which broadcasts to every live room for that PC.

This design makes cross-PC forwarding use an explicit room target while preserving relay opacity. The relay validates the relay-owned wrapper fields (`to_pc`, `to_room`, `envelope` object), verifies sibling authorization by authenticated `sender_peer_id` and `to_pc`, carries the generic envelope body verbatim, and sends only to `(to_pc, to_room)`. Any `session_id` remains endpoint-owned data inside `ct`, room metadata, or the generic envelope body; the relay never parses it, logs it, indexes it, or metrics-tags it.

## Refactor Steps

### Step 1: Add explicit cross-PC room target parsing
**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / fail-fast boundary  
**Files**: `relay/src/handlers/pi_forward.rs`, generated future `PiEnvelopeFrame` schema/types, relay cross-PC tests  
**Story**: `epic-bold-canonical-session-relay-opaque-targeting-step-1`

**Current State**:
```rust
let to_pc = frame.get("to_pc").and_then(|v| v.as_str());
let envelope = frame.get("envelope");

let (to_pc, envelope) = match (to_pc, envelope) {
    (Some(t), Some(e)) if e.is_object() && !t.is_empty() => (t, e),
    _ => return PiForwardResult::TransportError(make_transport_error(frame.get("envelope"), "bad_envelope")),
};
```

**Target State**:
```rust
let to_pc = frame.get("to_pc").and_then(|v| v.as_str());
let to_room = frame.get("to_room").and_then(|v| v.as_str());
let envelope = frame.get("envelope");

let (to_pc, to_room, envelope) = match (to_pc, to_room, envelope) {
    (Some(pc), Some(room), Some(e))
        if !pc.is_empty() && !room.is_empty() && e.is_object() => (pc, room, e),
    _ => {
        return PiForwardResult::TransportError(make_transport_error(
            frame.get("envelope"),
            "bad_envelope",
        ));
    }
};
```

**Implementation Notes**:
- Treat `to_room` as relay-owned routing metadata only; do not derive it from `session_id` and do not parse the generic envelope body.
- Add tests for missing `to_room`, empty `to_room`, missing `to_pc`, non-object `envelope`, and valid `to_pc`/`to_room` extraction.
- Mirror the field into future generated cross-PC frame definitions; do not create a separate Rust-only target model once generated code lands.

**Acceptance Criteria**:
- [ ] `pi_envelope` with missing/empty `to_room` returns `bad_envelope` in the clean-room path.
- [ ] Valid `to_pc`/`to_room` frames proceed to authorization without inspecting `envelope.body`.
- [ ] Tests prove `session_id` inside the generic envelope body is irrelevant to relay parsing.
- [ ] Relay fmt/clippy/tests pass for the touched module.

**Rollback**: Revert the `to_room` extraction and tests; this restores the legacy `to_pc`-only parser but must be paired with re-enabling the old fanout path if later steps already landed.

---

### Step 2: Replace peer-wide fanout with room-targeted registry forwarding
**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / pattern drift  
**Files**: `relay/src/peers/registry.rs`, `relay/src/handlers/pi_forward.rs`, registry tests  
**Story**: `epic-bold-canonical-session-relay-opaque-targeting-step-2`

**Current State**:
```rust
pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool {
    let lock = self.senders.lock().unwrap();
    let mut delivered = false;
    for ((p, _), v) in lock.iter() {
        if p == peer_id {
            for (_, _, tx) in v.iter() {
                if tx.send(msg.clone()).is_ok() {
                    delivered = true;
                }
            }
        }
    }
    delivered
}
```

**Target State**:
```rust
pub fn forward_to_room(&self, peer_id: &str, room_id: &str, msg: Message) -> bool {
    const EXTERNAL_CONN_ID: u64 = u64::MAX;
    self.forward(peer_id, room_id, msg, EXTERNAL_CONN_ID)
}
```

**Implementation Notes**:
- Use the existing `(peer, room)` registry key and sender-list semantics; do not add session keys or secondary indexes.
- Keep `forward_to_all_rooms_of` private for presence/rooms control pushes; it is not a data-plane cross-PC forwarding API.
- Delete `forward_to_peer` if no call sites remain, or make any temporary legacy call site private and explicitly deprecated.
- Add a regression test with one destination peer connected to `main` and `work`: forwarding to `work` must not deliver to `main`.

**Acceptance Criteria**:
- [ ] `pi_forward` no longer calls `forward_to_peer`.
- [ ] Cross-PC data-plane forwarding uses `PeerRegistry::forward` or a thin `forward_to_room` helper over `(peer, room)`.
- [ ] Tests prove two live rooms for the same destination peer receive only the addressed room.
- [ ] No public peer-wide data-plane helper remains without an explicit control-plane-only reason.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Restore `forward_to_peer` and the old `pi_forward` call. This cleanly reopens fanout and should only be used as an emergency rollback.

---

### Step 3: Preserve transport-error semantics and inbound target metadata
**Priority**: High  
**Risk**: Medium  
**Source Lens**: fail-fast boundary / generated-contract preparation  
**Files**: `relay/src/handlers/pi_forward.rs`, `relay/src/handlers/peer.rs`, relay cross-PC tests  
**Story**: `epic-bold-canonical-session-relay-opaque-targeting-step-3`

**Current State**:
```rust
let outbound = serde_json::json!({
    "type": "pi_envelope_in",
    "from_pc": sender_peer_id,
    "envelope": envelope, // verbatim
});
let msg = Message::Text(outbound.to_string());

if registry.forward_to_peer(to_pc, msg) {
    PiForwardResult::Forwarded
} else {
    PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
}
```

**Target State**:
```rust
let outbound = serde_json::json!({
    "type": "pi_envelope_in",
    "from_pc": sender_peer_id,
    "to_room": to_room,
    "envelope": envelope, // verbatim
});
let msg = Message::Text(outbound.to_string());

if registry.forward_to_room(to_pc, to_room, msg) {
    PiForwardResult::Forwarded
} else {
    PiForwardResult::TransportError(make_transport_error(Some(envelope), "offline"))
}
```

**Implementation Notes**:
- Keep authorization order: validate wrapper shape, verify `sender_peer_id`/`to_pc` sibling membership, then route to `to_room`.
- Unknown `to_room` under an online `to_pc` returns the existing `offline` transport error because the addressed target is not live.
- Include `to_room` in `pi_envelope_in` so the receiving extension can validate that the inbound target matches the local connection/session guard; do not include or derive `session_id` at the relay.
- Preserve `_relay` error envelope fields: `from: "_relay"`, `to` copied from original `envelope.from` when present, fresh id, `re` copied from original id, and `body.reason`.

**Acceptance Criteria**:
- [ ] Successful `pi_envelope` delivery emits `pi_envelope_in` with `from_pc`, `to_room`, and verbatim `envelope`.
- [ ] Unknown destination room returns `transport_error: offline` correlated to the original envelope id.
- [ ] `not_authorized` and `bad_envelope` behavior remains compatible with `PROTOCOL.md`.
- [ ] No relay logs or errors include `ct`, generic envelope body content, or `session_id`.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Revert `pi_envelope_in.to_room` emission and route through `forward_to_peer`; transport-error helper can remain if unchanged.

---

### Step 4: Lock the opaque relay boundary with regression tests and comments
**Priority**: Medium  
**Risk**: Low  
**Source Lens**: boundary clarity / dead weight  
**Files**: `relay/src/handlers/pi_forward.rs`, `relay/src/peers/registry.rs`, `relay/src/rooms.rs`, `relay/src/protocol/outer.rs`, relay tests  
**Story**: `epic-bold-canonical-session-relay-opaque-targeting-step-4`

**Current State**:
```rust
// registry.rs today exposes both targeted forward(...) and peer-wide forward_to_peer(...).
// pi_forward.rs conventionally treats envelope as verbatim, but has no room-target regression test.
```

**Target State**:
```rust
// Cross-PC data-plane forwarding is always room-targeted: (to_pc, to_room).
// Any session_id inside ct, room metadata, or AgentEnvelope.body is endpoint-owned opaque data.
```

**Implementation Notes**:
- Add a test that embeds `session_id` in `envelope.body` and proves the forwarded `pi_envelope_in.envelope` is byte/JSON-value equivalent except for relay-owned wrapper fields.
- Add a targeted-room regression test that registers two rooms under one peer and proves only `to_room` receives the frame.
- Remove stale comments that say cross-PC lacks room knowledge (`"where the relay has Pi-B's pubkey but not its room_id"`). Replace with the room-targeted invariant.
- Keep `RoomMeta.session_id` documented as opaque bootstrap metadata; it is not a routing key, lookup key, log key, or metric dimension.

**Acceptance Criteria**:
- [ ] Tests fail if `pi_forward` parses or branches on `session_id`.
- [ ] Comments and module docs no longer describe peer-wide fanout as the expected cross-PC path.
- [ ] `RoomMeta.session_id` remains opaque metadata and is not used by registry lookup or forwarding.
- [ ] Relay fmt/clippy/tests pass.

**Rollback**: Revert the tests/comments only if they block an emergency rollback to peer-wide forwarding; do not leave comments claiming room-targeted routing while fanout is restored.

## Implementation Order

1. `epic-bold-canonical-session-relay-opaque-targeting-step-1` (depends on `epic-bold-canonical-session-identity-model`)
2. `epic-bold-canonical-session-relay-opaque-targeting-step-2` (depends on step 1)
3. `epic-bold-canonical-session-relay-opaque-targeting-step-3` (depends on step 2)
4. `epic-bold-canonical-session-relay-opaque-targeting-step-4` (depends on step 3)

## Atomic steps acknowledged

- Step 2 is the behavior-switch step: it retires peer-wide delivery for cross-PC data-plane frames. It is rollback-isolated by restoring `forward_to_peer` and the old `pi_forward` call.
- Step 3 changes the inbound `pi_envelope_in` wrapper by adding `to_room`. Generated-protocol and typed-actor implementations must include this relay-owned field rather than creating a second compatibility-only frame.
- Missing-`to_room` compatibility is intentionally not normalized into `main`; if implementation needs a temporary seam, it must be explicit and removable so the relay does not fail open again.

## Verification plan

For implementation stories, run from `relay/`:

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
```
