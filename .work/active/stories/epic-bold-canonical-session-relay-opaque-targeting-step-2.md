---
id: epic-bold-canonical-session-relay-opaque-targeting-step-2
kind: story
stage: done
tags: [refactor, bold, relay]
parent: epic-bold-canonical-session-relay-opaque-targeting
depends_on: [epic-bold-canonical-session-relay-opaque-targeting-step-1]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Step 2: Replace peer-wide fanout with room-targeted registry forwarding

## Current State

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

## Target State

```rust
pub fn forward_to_room(&self, peer_id: &str, room_id: &str, msg: Message) -> bool {
    const EXTERNAL_CONN_ID: u64 = u64::MAX;
    self.forward(peer_id, room_id, msg, EXTERNAL_CONN_ID)
}
```

## Implementation Notes

- Use the existing `(peer, room)` registry key and sender-list semantics; do not add session keys or secondary indexes.
- Keep `forward_to_all_rooms_of` private for presence/rooms control pushes; it is not a data-plane cross-PC forwarding API.
- Delete `forward_to_peer` if no call sites remain, or make any temporary legacy call site private and explicitly deprecated.
- Add a regression test with one destination peer connected to `main` and `work`: forwarding to `work` must not deliver to `main`.

## Acceptance Criteria

- [ ] `pi_forward` no longer calls `forward_to_peer`.
- [ ] Cross-PC data-plane forwarding uses `PeerRegistry::forward` or a thin `forward_to_room` helper over `(peer, room)`.
- [ ] Tests prove two live rooms for the same destination peer receive only the addressed room.
- [ ] No public peer-wide data-plane helper remains without an explicit control-plane-only reason.
- [ ] Relay fmt/clippy/tests pass.

## Risk

High. This is the behavior-switch step that retires legacy peer-wide cross-PC delivery. It is necessary to prevent cross-room/session contamination.

## Rollback

Restore `forward_to_peer` and the old `pi_forward` call. This cleanly reopens fanout and should only be used as an emergency rollback.

## Implementation notes
- Files changed: `relay/src/peers/registry.rs`, `relay/src/handlers/pi_forward.rs`.
- Tests added: targeted registry regression for two live rooms under one peer; targeted `pi_envelope` regression proving authorized forwarding reaches only `to_room` and carries the opaque envelope unchanged.
- Discrepancies from design: included `to_room` on `pi_envelope_in` while switching the data-plane route so the receiver has the explicit target metadata expected by the next step; relay still treats `session_id` as opaque body data.
- Adjacent issues parked: none.
- Verification: `cargo fmt --check` passed; `cargo test authorized_forward_targets_only_to_room` passed; `cargo test forward_to_room_targets_one_room_not_every_room_for_peer` passed.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Inspected implementation commit `f6ed43c`; `pi_forward` now forwards via explicit `to_room`, `forward_to_peer` is removed, `pi_envelope_in` carries `to_room`, and tests prove two rooms for one peer only deliver to the addressed room while preserving the inner envelope verbatim. Relay code does not parse inner `ct`/`body.session_id`. Verification run from `relay/`: `cargo fmt --check && cargo clippy -- -D warnings && cargo test`.
