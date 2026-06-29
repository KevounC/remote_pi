---
id: epic-bold-canonical-session
kind: epic
stage: drafting
tags: [refactor, bold, pi-extension, app, relay, cockpit, security]
parent: null
depends_on: [epic-bold-generated-protocol]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Session is a first-class identity — the five notions are secretly one

## Thesis
`RemoteSession` is the canonical identity of one coding-agent session. The relay
room, the app Hive key, the cwd-derived room id, the Pi SDK runtime session, and
the cockpit JSONL path are all projections of it. Name it once.

## Lens
Domain Crystallization

## Impact
There are five overlapping "session" identities, none canonical: Pi SDK runtime
session (`session_start`/`session_shutdown`), relay room key `(peer_id,
room_id)`, pi-extension cwd-derived `roomIdFor(cwd, name)` (`rooms.ts:43`), app
Hive key `<epk>:<roomId>` (`boxes.dart:8`), cockpit JSONL session path
(`session_info.dart`). "Working" is computed four ways against these. The wire
carries **no** session discriminator — the exact root cause of the
cross-session contamination bug: a peer in a different cwd woke showing another
session's last turn and none of its own (live-reproduced when an Explore
subagent's stream contaminated into the operator's viewed session).

A canonical `RemoteSession` (stable session id, owns cwd, room, model, thinking,
started_at, working, transcript) becomes the single key for relay routing, app
Hive boxes, persistence, UI tiles, cwd-lock identity, working indicator, and
transcript. `RemotePeer` / `RemotePc` / `RemoteRoom` sit beside it. The relay
routes to `(to_pc, to_room)` and carries `session_id` **opaquely** — it doesn't
understand session semantics, just targets it; app and extension validate
`session_id` fail-closed. The whole cross-session-bleed class becomes
impossible, not patched.

**Supersedes** `feature-session-isolation-wire-discriminator` — that feature is
the bugfix slice (add `session_id` to the wire, fail-closed); this epic is the
reconception. The feature's brief/root-cause/diagnosis becomes the first child
story (`epic-bold-canonical-session-wire-discriminator`).

## Cost
Touches every subsystem's identity model. The hardest architectural call: does
the relay *learn* about sessions, or stay a room-router that carries `session_id`
opaquely? This epic's answer (opaque carry + endpoint validation) keeps the
relay dumb and the session domain on the endpoints — but that's the feasibility
question the riskiest child resolves. Reconciles with the clean-room breaking
change already locked (required + fail-closed `session_id`).

## Child features (riskiest first)
- **epic-bold-canonical-session-identity-model** *(riskiest — design this first;
  the relay's session posture — opaque carry vs. session-aware — is the
  architectural call the rest hangs on)* — the `RemoteSession` /
  `RemotePeer` / `RemotePc` / `RemoteRoom` domain types and their relationship
  to relay routing.
- epic-bold-canonical-session-wire-discriminator — the migrated
  session-isolation bugfix: required `session_id` on every chat-bearing
  ServerMessage, fail-closed validation. Absorbs
  `feature-session-isolation-wire-discriminator` and
  `relay-cross-pc-room-targeting`.
- epic-bold-canonical-session-relay-opaque-targeting — relay forwards to
  `(to_pc, to_room)`, carries `session_id` opaquely; retires `forward_to_peer`
  fanout (`relay/src/peers/registry.rs:369`).
- epic-bold-canonical-session-app-attribution-hydration — app validates
  `session_id` before accepting; `_applyHistory` refuses foreign sessions;
  retires the "legacy no-room routes unconditionally" path.
