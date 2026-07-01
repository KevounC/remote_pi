---
id: story-to-room-sender-side-room-targeting
kind: story
stage: drafting
tags: [pi-extension, bug, security]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-relay-opaque-targeting]
release_binding: extension-0.6.0
gate_origin: null
created: 2026-07-01
updated: 2026-07-01
---

# to_room sender-side room-targeting (cross-PC pi-envelope)

## Brief

The relay half of the `to_room` wire change shipped in relay-0.2.0
(`epic-bold-canonical-session-relay-opaque-targeting`): cross-PC
`pi_envelope` now carries a required `to_room`, the relay routes via
`send_to_room(to_pc, to_room)` (not peer-wide fanout), empty `to_room` →
`bad_envelope`, and `pi_envelope_in` echoes `to_room`.

The **sender half was left as a temporary `"main"` default** (commit
`13701ee`, `broker_remote.ts:357,466,531`). This is broken: each Pi's
MeshNode joins `roomIdFor(cwd, sessionName)` — a real 12-char id, NOT
`"main"` — so a `to_room: "main"` envelope reaches no live sibling room and
the relay returns `transport_error: offline`. Cross-PC mesh delivery is
currently non-functional for any real room.

This story threads the destination sibling's actual room through the three
hardcoded `"main"` call sites in `broker_remote.ts`.

## Root cause

`broker_remote.ts` was given the `sendEnvelopeToPi(toPc, toRoom, env)`
signature but passed a literal `"main"` at all three sites because the
sender had no path to the destination room. The relay correctly rejects
empty/missing `to_room` and returns `offline` for an unknown room — so the
hardcode silently breaks delivery rather than failing loud at the sender.

## Design — derivation, not a new protocol field

**Key insight:** the destination room is *derivable* from data the sender
already caches. There is no need for a new wire field or a separate
room-discovery round-trip.

### The room model (grounded)

- `relay/src/peers/connections.rs:54-72`: a relay peer may hold entries at
  multiple `(peer_id, room_id)` keys — one per joined room.
- `pi-extension/src/session/mesh_node.ts:210-218`: the MeshNode joins
  **exactly one** room — `roomIdFor(params.cwd, roomName)` — on the leader.
  Every local UDS peer in that MeshNode shares that single relay room.
- `pi-extension/src/rooms.ts`: `roomIdFor(cwd, name)` is THE single
  derivation (default-preserving: unnamed agent → `roomIdForCwd`).
- `broker_remote.ts` caches each sibling's local roster as
  `WirePeerInfo[] = { cwd, name, address }[]` via `peers_update` — exactly
  the inputs to `roomIdFor`.

Therefore: **the sibling's leader room = `roomIdFor(info.cwd, info.name)`**
for any roster entry `info` of that sibling. All of a sibling's roster
peers share one room (the leader's), so any cached roster entry yields the
same room id.

### The three call sites

#### Site 1 — `tryRouteOutbound` (line 357): data envelope to `env.to`

`env.to = "<pcLabel>:<peerName>"`. After `parseAddress`, `peerName` is the
sibling-local address (e.g. `<cwd>@<name>`). Match `peerName` against the
cached roster for `pcLabel`; derive the room via `roomIdFor(info.cwd,
info.name)`.

- **Cache hit**: send to the derived room.
- **Cache miss**: the existing `peers_request` warms the cache, but the
  *current* envelope cannot be sent (no room to target). Currently the code
  optimistically sends to `"main"` (harmless no-op → offline) and times out
  via ACK. After the fix, on a hard cache miss the sender should **still
  send** to avoid changing the optimistic-send contract, but the ACK timeout
  already surfaces the failure. Simplest correct behavior: derive from roster
  when present; when absent, log + let the ACK timeout report it (do NOT
  hardcode a room). Confirm this converges: the `peers_request` round-trip
  fills the cache, so the *next* send derives correctly.

#### Site 2 — `handleIncoming` ACK (line 466): reply to `env.from`

The ACK replies to the sibling that sent the inbound envelope. The sibling's
room is **the room the sibling targeted on the way in** — which the relay
echoes as `to_room` on the `pi_envelope_in` frame. Currently
`PiForwardClient._handleLine` (line 103) emits only `[env, fromPc]`,
**discarding `to_room`**.

Fix: thread the inbound `to_room` through the `envelope` event so
`handleIncoming` receives it, and use it as the ACK's `to_room`. This is the
cleanest source: the relay already validated it, and it is by construction the
sender's live room (the room that just reached us).

- Update `PiForwardClientEvents.envelope` to `[env, fromPc, toRoom]`.
- Update `handleIncoming(env, fromPc, toRoom)` signature.
- ACK targets `toRoom` (the inbound frame's `to_room`).

#### Site 3 — `_sendControlEnvelope` (line 531): control to `<sibling>:_broker_remote`

`_broker_remote` is a synthetic control endpoint, never a roster peer — so
its room cannot be derived from a roster match on the name. But the sibling's
control endpoint lives in the sibling's **leader room**, which IS the room of
any of the sibling's cached roster peers (they all share the leader's room).

Fix: derive the sibling's room from **any** cached roster entry for that
`pcLabel` (`_remoteInfos(pcLabel)[0]` → `roomIdFor`). 

- **Warm cache** (roster present): derive from the first entry. All entries
  share the room, so any works.
- **Cold cache** (no roster yet — bootstrap): this is the real
  chicken-and-egg. The existing `_bootstrapWithSiblings` fires
  `peers_request` at every sibling; until the first `peers_update` returns,
  the sender cannot derive a room. Two options:
  - (a) Drop the control send when the room is unknown and rely on the
    reannounce timer to retry after the cache warms. Risk: the very first
    `peers_request` that should *warm* the cache is itself a control send
    that gets dropped → deadlock.
  - (b) Have the sibling MeshNode join a **well-known control room** in
    addition to its leader room, and target that for control envelopes.
    Relay already supports multi-room per peer. This is the robust option:
    control never depends on roster state.
  - **Recommended: (b)** — a dedicated control room (e.g. the literal
    `"main"`, or a derived `_control` room) joined by every MeshNode
    alongside its leader room. Control envelopes target it; data envelopes
    target the derived leader room. Reuses the relay's existing multi-room
    support; no new wire field.

Decide (a) vs (b) during implementation. (b) is more code (MeshNode joins a
second room) but eliminates the bootstrap deadlock; (a) is less code but
strands the first `peers_request` until an out-of-band roster arrives. The
current `peers_update` push from siblings already fills the cache
independently of our own `peers_request`, so (a) may actually work in
practice (the sibling's reannounce timer pushes to us) — verify with a test.

## Acceptance criteria

- [ ] No `"main"` literal remains as a `toRoom` argument in
  `broker_remote.ts` (the three sites derive or thread the real room).
- [ ] A cross-PC data envelope to a sibling peer in a non-`main` room is
  delivered (relay routes to the derived room, not `main`).
- [ ] The ACK reply targets the inbound frame's `to_room` (threaded through
  `PiForwardClient`, not hardcoded).
- [ ] Control envelopes reach the sibling's leader room (derived or via a
  control room), with the bootstrap case analyzed and tested.
- [ ] Cold-cache data send converges: cache warms via `peers_update` and the
  next send succeeds (no permanent `offline`).
- [ ] Existing `broker_remote.test.ts` assertions updated: the test at
  line 633 (`pi.sendEnvelopeToPi("K_B", "main", ...)`) and siblings must
  assert the *derived* room, not `"main"`.
- [ ] `corepack pnpm typecheck`, `corepack pnpm test`, `corepack pnpm build`
    pass.

## Implementation notes

- `roomIdFor` is already imported in `mesh_node.ts`; `broker_remote.ts`
  will need to import it from `../rooms.js`.
- The `peers_detailed` roster already carries `{cwd, name}` — the exact
  `roomIdFor` inputs. No wire change.
- Keep the optimistic-send + ACK-timeout contract intact; the fix changes
  *which room* is targeted, not whether a send is attempted.
- This is fork-private behavior (not an upstream PR); the `to_room` wire
  field is already the canonical shape.

## Why this is a story, not inline

The handoff note described this as "thread it through," but it is
genuinely design-bearing: the inbound `to_room` is discarded today,
control envelopes face a bootstrap problem, and the roster-derivation
approach is a non-obvious single-source-of-truth design (not a new wire
field). Scoping it as a tracked story with acceptance criteria keeps the
release honest and gives the gates a concrete artifact to verify.

## Verification

From `pi-extension/`:

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```
