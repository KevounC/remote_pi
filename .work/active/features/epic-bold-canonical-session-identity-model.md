---
id: epic-bold-canonical-session-identity-model
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-canonical-session
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — identity model (riskiest — design first)

## Brief
The `RemoteSession` / `RemotePeer` / `RemotePc` / `RemoteRoom` domain types and
their relationship to relay routing. A canonical `RemoteSession` (stable
session id, owns cwd, room, model, thinking, started_at, working, transcript) is
the single key for relay routing, app Hive boxes, persistence, UI tiles,
cwd-lock identity, working indicator, and transcript.

The riskiest architectural call: does the relay *learn* about sessions, or stay
a room-router that carries `session_id` **opaquely**? This epic's answer is the
latter — opaque carry + endpoint validation — keeping the relay dumb and the
session domain on the endpoints. This feature must prove that posture is
sufficient before the wire-discriminator and relay-targeting children commit to
it.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: riskiest child — the relay's session posture is the architectural
  call the rest of the epic hangs on. Design FIRST.

## Foundation references
- Evidence of the five overlapping identities: Pi SDK runtime
  (`pi-extension/src/index.ts:1550-1625`), relay room key
  (`relay/src/peers/registry.rs:1-70`), cwd-derived room id
  (`pi-extension/src/rooms.ts:43`), app Hive key (`app/lib/data/local/boxes.dart:8`),
  cockpit JSONL path (`cockpit/lib/app/cockpit/domain/entities/session_info.dart:1-22`).

<!-- /agile-workflow:refactor-design pins the identity types + relay posture. -->
