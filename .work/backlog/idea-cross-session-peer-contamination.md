---
id: idea-cross-session-peer-contamination
created: 2026-06-29
updated: 2026-06-29
tags: [app, relay, pi-extension, bug]
---

# Cross-session / cross-peer contamination: wrong session's turn appears in a different peer on wake

Operator-observed during the mobile chat-surface testing conversation:

1. Had a peer that was previously in a **different cwd** than this session.
2. This chat appears to have **cross-pollinated into that peer** — i.e. messages
   from *this* session showed up associated with a *different* peer/session that
   should have been isolated by cwd/session identity.
3. When sessions woke back up on mobile, that peer's session showed **this
   session's last turn and nothing else visible** — a single stray turn from the
   wrong session, and the rest of that peer's own transcript not rendered.

Two distinct things look broken:

- **Session/peer isolation on the relay or in routing.** Messages from one
  session are landing in a peer that was in a different cwd. This suggests the
  room/session targeting or peer identity isn't being scoped correctly — possibly
  a room membership / session-id / cwd mismatch where an update for session A is
  being routed or attributed to peer B. Could be on the relay (cross-PC / mesh
  forwarding targeting the wrong room/peer), in the pi extension (emitting
  session updates without the right session/peer identity), or in the app
  (attributing incoming updates to the wrong local session view).
- **Transcript hydration on wake shows only the stray turn.** After the
  contamination, the affected peer's mobile session wakes with just the one
  foreign turn and none of its own history. That's either (a) the contaminating
  message overwrote/ replaced the transcript tail instead of appending, or (b)
  the wake-time hydration is fetching from a contaminated/wrong session source
  and only that one turn is present.

This is a correctness bug in the session-isolation / routing layer, not just a
UI polish issue. Before fixing, needs:

- reproduction of the cross-cwd contamination path (which peer/room/session ids
  were involved, and how the two sessions were related on the relay/mesh);
- a check of whether the relay forwarded an update to the wrong room/peer, or
  the extension emitted it with the wrong session identity, or the app attributed
  it to the wrong local session;
- a look at `PROTOCOL.md` for the room/session metadata and cross-PC targeting
  rules, since this likely intersects cross-PC forwarding and session-replacement
  semantics.

Likely touches `relay/` (routing/room/peer targeting), `pi-extension/` (session
identity on emitted updates), and `app/` (attribution + transcript hydration on
wake). Treat as high-priority because it's silent data corruption of a session's
transcript across peers.
