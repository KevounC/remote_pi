---
id: feature-session-isolation-wire-discriminator
kind: feature
stage: drafting
tags: [app, pi-extension, relay, bug, security]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Session isolation: per-message wire discriminator

## Brief

Chat-bearing `ServerMessage`s (`user_message`, `agent_chunk`, `agent_done`,
`session_history`, and the `queued_message_state`/tool surfaces) carry **no
session discriminator** — no session id, no room, no cwd, no peer field. The
protocol comment says it outright: `app/lib/protocol/protocol.dart:752` — *"1
pairing = 1 session: no session_id on any message."* The system relies
**entirely** on the relay's outer-envelope `room` field to demux, and that
boundary is insufficient and fails open in two places, producing silent
cross-session transcript contamination.

Observed symptom: a peer previously in a different cwd woke on mobile showing
**another session's last turn and none of its own transcript**. During the
diagnosis of that very bug, the operator reproduced it live by responding to an
Explore subagent's chat session instead of the orchestrator's — the subagent's
stream contaminated into the session the operator was viewing. This is silent
data corruption of a session's transcript across peers, not a UI render glitch.

The fix adds a canonical session discriminator to every chat-bearing
`ServerMessage`, makes relay room-targeting real (absorbing
`relay-cross-pc-room-targeting`), and fail-closes app attribution/hydration so a
foreign message can never be written to the wrong session's transcript box.

## Strategic decisions

- **Discriminator field: canonical `session_id`** — a separate canonical session
  identity dimension, not a reuse of the existing relay outer `room`. Cleaner
  long-term: `room` is a transport/routing concern owned by the relay, while
  `session_id` is the pi-extension-owned identity of the coding-agent session the
  message belongs to. Keeping them distinct means session identity survives
  transport changes (room renames, relay fanout redesign, future P2P) and gives a
  single self-describing field every consumer can validate. The relay's outer
  `room` stays as a transport-level demux optimization, not the correctness
  boundary.
- **Compatibility: breaking / required / fail-closed** — the fork is treated as
  clean-room/greenfield; upstream compatibility is explicitly not a constraint.
  The new `session_id` field is REQUIRED on every chat-bearing `ServerMessage`;
  receivers (app, and the receiving pi-extension broker on cross-PC) fail-closed
  (drop + log) when it is absent or does not match the active session. No
  "legacy no-room frame" unconditional acceptance path survives for chat-bearing
  messages. This closes the vulnerability rather than leaving it open for legacy
  peers.
- **Absorb `relay-cross-pc-room-targeting`** — that backlog item is the relay
  half of this same bug (cross-PC `pi_envelope` fans out to every live room on
  the destination PC). It becomes a child story of this feature so the
  contamination fix ships as one coherent protocol change rather than a
  fragmented relay-only patch. The relay-targeting work has no standalone value
  without the session discriminator on the wire.

## Root cause (diagnosis)

Chat-bearing `ServerMessage`s are not self-identifying. Confirmed across all
three subsystems (read-only Explore pass, 63 tool uses):

### pi-extension emission — no discriminator on broadcast

- `pi-extension/src/protocol/types.ts:93-154` — `user_message`, `agent_chunk`,
  `agent_done`, `queued_message_state` have no session/room/cwd field. Only
  `pair_ok` carries `room_id`; `session_history` carries `session_started_at`
  but not `room_id` or `session_id`.
- `pi-extension/src/index.ts:620-635` `_broadcastToActive()` fans every broadcast
  ServerMessage to all active owner channels for this pi-extension instance.
- `pi-extension/src/index.ts:3268-3314` `user_message` echo emission — no
  discriminator.
- `pi-extension/src/index.ts:1408-1413`, `:1473-1480` `agent_chunk`/`agent_done`
  — no discriminator.
- `pi-extension/src/transport/peer_channel.ts:63-80` — the outer envelope sent
  to the app strips `room` with a `NOTE: room removed until relay (W1.A) + app
  (W1.C) accept the field`. So even the outer-envelope demux is incomplete here.

### relay forwarding — cross-PC fanout to every live room

- `relay/src/handlers/pi_forward.rs:128-173` `handle_pi_envelope()` reads only
  `to_pc`; no `to_room`, no session id.
- `relay/src/peers/registry.rs:369-384` `forward_to_peer()` sends to **every**
  live `(peer, room)` matching the destination PC pubkey. Confirms the
  `relay-cross-pc-room-targeting` backlog item.
- Contrast: normal app↔Pi outer envelopes ARE room-targeted at
  `relay/src/handlers/peer.rs:440-484` (`(dest_peer, dest_room)`). So the
  cross-PC path is the outlier, not the norm.

### app attribution & hydration — accepts foreign messages, then replaces the box

- `app/lib/protocol/protocol.dart:749-779` — comment *"1 pairing = 1 session:
  no session_id on any message."*
- `app/lib/data/transport/ws_transport.dart:63-103` — drops a frame only when
  `senderRoom != null && senderRoom != activeRoom`. **Legacy/no-room frames
  route unconditionally.**
- `app/lib/data/sync/sync_service.dart:409-431` — `SyncService` gates inbound
  ServerMessages by peer epk only, not room; room-gating is deferred to
  `WsTransport`.
- `app/lib/data/sync/sync_service.dart:497-535` — live `user_message` written to
  the active session box via `_upsert`, which snapshots `_activeEpk/_activeRoomId`.
- `app/lib/data/sync/sync_service.dart:671-760` `_applyHistory()` — **replaces**
  the active session's message box with the incoming `session_history` rows,
  deleting local rows beyond the foreign length and overwriting low-sequence
  rows. This is the direct cause of *"B showed only A's stray turn and none of
  B's own transcript."*

## Reproduction hypothesis

1. Two sessions/rooms exist for the same paired peer/PC (session A, session B).
2. Mobile is viewing or re-entering session B, so `SyncService._activeEpk` /
   `_activeRoomId` are B.
3. A `session_history` (or chat update) from session A reaches the app while B is
   active, via any of: frame lacks outer `room`; frame has wrong outer `room`;
   transport active-room state stale during wake/re-enter; or cross-PC fanout
   delivers A traffic into a B-visible channel (the live reproduction — an
   Explore subagent's stream landing in the operator's viewed session).
4. Because `SessionHistory` carries no embedded session id, `_onServerMessage`
   accepts it.
5. `_applyHistory()` applies A's history to B's message box
   (`msgs_<epk>__<roomB>`), reconciling the box to A's rows and deleting B's.
6. Chat B's `watchMessages(epk, roomB)` emits the reconciled box → B renders
   exactly the foreign turn(s) and none of its prior transcript.

## Fix approach (high-level — detailed in feature-design)

A coherent protocol change across three subsystems, sequenced so the wire
contract and its consumers land together:

1. **pi-extension (emission + cross-PC broker):**
   - Add canonical `session_id` to every chat-bearing `ServerMessage`
     (`user_message`, `agent_chunk`, `agent_done`, `session_history`,
     `queued_message_state`, tool surfaces) in `pi-extension/src/protocol/types.ts`
     and every emission site in `index.ts`.
   - Restore `room` on the outer envelope sent to the app (the `peer_channel.ts`
     NOTE flagged it as waiting on relay+app accepting it).
   - On the cross-PC receiving broker: verify the incoming `pi_envelope_in`
     targets a local session/room that exists before injecting into the broker
     /agent (fail-closed drop + log on mismatch), in addition to the existing
     anti-spoof `from_pc` prefix check.
2. **relay (room-targeted cross-PC forwarding — absorbs
   `relay-cross-pc-room-targeting`):**
   - Add `to_room` (or equivalent) to the cross-PC `pi_envelope` frame.
   - `handle_pi_envelope()` forwards to `(to_pc, to_room)` via the existing
     room-targeted `registry.forward()`, NOT the fanout `forward_to_peer()`.
   - `forward_to_peer()` is retired for this path (or scoped to genuinely
     broadcast cross-PC control frames if any exist — verify during design).
3. **app (fail-closed attribution + hydration):**
   - Require `session_id` on every chat-bearing ServerMessage; drop + log when
     absent (retire the "legacy no-room routes unconditionally" path for
     chat-bearing messages).
   - `_onServerMessage` validates the embedded `session_id` against the active
     session before accepting; mismatch → drop + log.
   - `_applyHistory()` additionally guards: refuse to apply a `session_history`
     whose `session_id` != active session, so a foreign history can never
     replace the local transcript box. This is the direct fix for the
     "only the stray turn" symptom.
   - SyncService + WsTransport: lift the room/session demux from
     transport-optimization to correctness boundary.
4. **protocol contract (`PROTOCOL.md`):**
   - Document `session_id` as a required field on chat-bearing ServerMessages.
   - Document `to_room` on cross-PC `pi_envelope` and the fail-closed
     receiver/drop+log semantics.
   - Remove the "1 pairing = 1 session: no session_id" assumption in favor of
     explicit per-message session identity (rolling-foundation: rewrite the
     section in place, no migration prose).

## Verification plan (high-level)

- **Cross-language contract test:** a foreign `session_history`/`user_message`
  (wrong `session_id`) is dropped by the app, never written to the wrong box.
- **pi-extension:** emission tests assert `session_id` present on all
  chat-bearing ServerMessages; cross-PC broker rejects mis-targeted
  `pi_envelope_in`.
- **relay:** `handle_pi_envelope` forwards only to `(to_pc, to_room)`;
  no fanout to other rooms on the destination PC.
- **app:** `_applyHistory` refuses foreign `session_id`; `_onServerMessage`
  drops foreign chat messages; the "only the stray turn" symptom cannot
  reproduce.
- **Reproduce-then-fix:** reconstruct the live reproduction path (subagent
  stream contaminating into a viewed session) as a deterministic test where
  feasible; otherwise document as a smoke recipe.

## Stop-gap option (out of scope unless requested)

A narrow app-only guard — reject `session_history` whose `session_started_at`
doesn't match the active session — would stop the transcript-replacement
symptom *without* a protocol change, but leaves the missing-discriminator root
cause and the cross-PC fanout open. Not bundled here; can be split as a
separate `fix` story if a stop-gap is wanted before the protocol change lands.

## Source backlog items absorbed

- `.work/backlog/idea-cross-session-peer-contamination.md` (operator report +
  diagnosis) — absorbed as this feature's brief/root-cause/repro.
- `.work/backlog/relay-cross-pc-room-targeting.md` (relay fanout half) —
  absorbed as the relay child story of this feature.

## Next

`/agile-workflow:feature-design` decomposes this into child stories with a
`depends_on` chain (likely: pi-extension wire emission → relay `to_room`
targeting → app fail-closed validation → `PROTOCOL.md` update → cross-language
contract test), then advances `drafting → implementing`.
