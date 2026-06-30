---
id: epic-bold-canonical-session-identity-model-step-4
kind: story
stage: review
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session-identity-model
depends_on: [epic-bold-canonical-session-identity-model-step-3]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-30
---

# Step 4: Preserve relay opacity and route only by peer/room

## Current State
```rust
// relay/src/protocol/outer.rs
pub struct OuterEnvelope {
    pub peer: String,
    #[serde(default = "default_room")]
    pub room: String,
    pub ct: String,
}
```

```rust
// relay/src/peers/registry.rs
pub fn forward_to_peer(&self, peer_id: &str, msg: Message) -> bool {
    // cross-PC fanout to every live room of a peer
}
```

The app/Pi path already carries payload opaquely in `ct`, but legacy default-room behavior and cross-PC peer-wide fanout make room/session attribution fail open.

## Target State
```rust
// Relay routing remains session-blind.
pub struct OuterEnvelope {
    pub peer: String,
    pub room: String, // required in clean-room mode; no session_id here
    pub ct: String,   // opaque; may contain inner JSON with session_id
}

// Cross-PC targeting routes by peer + room, never by session_id.
registry.forward(to_pc, to_room, Message::Text(pi_envelope_in), EXTERNAL)
```

`session_id` stays inside endpoint-owned payloads (`ct` for app↔Pi; generic envelope body for Pi↔Pi). The relay may require explicit room/`to_room` to avoid fanout, but it never stores, parses, logs, compares, or routes by `session_id`.

## Implementation Notes
- Add relay tests that inject `session_id` inside `ct` or inside `pi_envelope.envelope.body` and prove relay output is byte/verbatim equivalent except for existing outer peer/from_pc rewrites.
- Make missing outer `room` fail closed in the clean-room path instead of defaulting to `main`; any temporary legacy parser must be isolated and marked removable.
- For cross-PC, the long-term target is `to_room`/room-addressed forwarding (owned by sibling `epic-bold-canonical-session-relay-opaque-targeting`). This story pins the invariant: the chosen cross-PC field is room targeting, not relay-learned sessions.
- Keep relay logs to peer tails, room ids, frame type names, sizes, and reasons. Never log `ct`, `session_id`, transcript, or tool args.

## Acceptance Criteria
- [ ] Relay has no `SessionId`/`session_id` domain field, registry key, database column, or routing branch.
- [ ] Relay tests prove `session_id` inside opaque payloads is carried unchanged and uninspected.
- [ ] Missing/legacy outer room handling is fail-closed or isolated behind a temporary compatibility seam with tests proving it cannot route to every active room.
- [ ] Cross-PC design notes/tests assert explicit room targeting and reject peer-wide fanout as the long-term path.
- [ ] `cargo fmt --check` and targeted relay tests pass.

## Risk
Medium. Tightening missing-room behavior is a breaking change for legacy peers; acceptable for this fork-private bold refactor, but sequence it after app/extension carry explicit rooms.

## Rollback
Restore `OuterEnvelope` default-room parsing and `forward_to_peer` usage. This reopens the known fanout risk, so only roll back together with endpoint validation if a deployment needs emergency legacy compatibility.

## Implementation notes
- Files changed: `relay/src/protocol/outer.rs`, `relay/tests/integration.rs`.
- Tests added: `rejects_missing_room`, `preserves_opaque_ct_that_mentions_session_id` in `relay/src/protocol/outer.rs`; updated integration outer-envelope routing tests to send explicit room and assert room rewrite.
- Discrepancies from design: `RoomMeta.session_id` remains as endpoint-owned bootstrap metadata from prior identity-model work; it is not a registry key, DB field, or routing branch. The unused generated mirror under `relay/src/protocol/generated/` still reflects the old generated schema and is intentionally left for the generated-protocol owner rather than hand-editing generated code.
- Adjacent issues parked: none.

## Review bounce (2026-06-29)

**Verdict**: Request changes

**Blockers**:
- `relay/src/protocol/generated/outer.rs:16` and `relay/src/protocol/outer.rs:65`: missing outer `room` still defaults to `"main"`, and the unit test asserts that behavior. This violates the fail-closed/temporary-compatibility-seam criterion and can still route a missing-room envelope to an active room.
- `relay/src/rooms.rs:17`, `relay/src/auth/challenge.rs:34`, and `relay/src/peers/registry.rs:302`: the relay still owns and mutates `session_id` as room metadata. It may not route by it, but the acceptance criterion literally says the relay has no `SessionId`/`session_id` domain field.
- `relay/tests/integration.rs:16`: commit `4ad5f2e0` updates the integration route test to send an explicit room, but its `ct` is only `"aGVsbG8="`. It proves room rewrite and generic `ct` preservation, not an integration boundary carrying a `session_id` inside opaque app↔Pi payload unchanged/uninspected.

**Acceptance criteria**:
- FAIL — Relay has no `SessionId`/`session_id` domain field, registry key, database column, or routing branch: `RoomMeta.session_id` and patch handling remain in relay source.
- PARTIAL/FAIL — Relay tests prove `session_id` inside opaque payloads is carried unchanged and uninspected: unit/Pi-forward coverage exists, but the changed integration test does not prove app↔Pi opaque `ct` with `session_id` through routing.
- FAIL — Missing/legacy outer room handling is fail-closed or isolated behind a temporary compatibility seam with tests proving it cannot route to every active room: generated outer envelope still defaults missing room to `main`.
- PASS — Cross-PC design/tests assert explicit room targeting and reject peer-wide fanout as the long-term path: `pi_envelope` requires `to_room`, and registry forwarding uses `forward_to_room`.
- PASS — `cargo fmt --check` and targeted relay tests pass: full relay verification passed.

**Verification run**:
- `cd /home/agent/forks/remote_pi && git show --stat --patch 4ad5f2e0 && git log --oneline -5` — inspected commit `4ad5f2e0` and adjacent history.
- `cd /home/agent/forks/remote_pi/relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test` — passed; full suite: 63 lib tests, 3 integration tests, 13 mesh tests, 6 pi-forward tests, 10 presence tests, 19 rooms tests, and doc-tests all green.

## Implementation notes (rework 2026-06-30)
- Files changed: `relay/src/protocol/generated/outer.rs`, `relay/src/protocol/outer.rs`, `relay/src/rooms.rs`, `relay/src/auth/challenge.rs`, `relay/src/auth/auth_test.rs`, `relay/src/handlers/peer.rs`, `relay/src/handlers/pi_forward.rs`, `relay/src/peers/registry.rs`, `relay/tests/integration.rs`.
- Fix 1 — missing outer `room` now fails closed: removed the `room = "main"` serde default from the generated outer mirror used by `parse_line`, added `deny_unknown_fields`, and replaced the unit test with `rejects_missing_room` plus `rejects_unknown_outer_field`. This is an intentional wire behavior change, not a pure refactor.
- Fix 2 — relay no longer owns mutable session metadata: removed `RoomMeta.session_id`, removed `ClientHelloRoomMeta.session_id`, removed `RoomMetaPatch.session_id`, and removed `room_meta_update` parsing/broadcast mutation for `session_id`. Remaining `session_id` strings in relay tests are opaque payload fixtures only.
- Fix 3 — integration coverage now carries opaque app↔Pi payload with session identity: `relay/tests/integration.rs` routes a `ct` value that is base64 for `{"session_id":"opaque-session","text":"hello"}` and asserts the relay rewrites only outer peer/room while preserving `ct` unchanged.
- Discrepancies from design: none; the relay remains session-blind and routes by peer/room. Hand-edited the generated outer mirror minimally because `parse_line` reexports it; did not regenerate schema/codegen in this stride per the coordination note.
- Adjacent issues parked: rust-codegen story should regenerate the outer schema/mirror so the generated source of truth also records required `room` and `deny_unknown_fields` without hand edits.
- Verification: `cd /home/agent/projects/remote_pi/relay && cargo fmt --check` — passed; `cd /home/agent/projects/remote_pi/relay && cargo clippy -- -D warnings` — passed; `cd /home/agent/projects/remote_pi/relay && cargo test` — passed (64 lib tests, 3 integration tests, 13 mesh tests, 6 pi-forward tests, 10 presence tests, 19 rooms tests, doc-tests all green).
