---
id: epic-bold-canonical-session-wire-discriminator
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app, relay, security, bug]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-identity-model, epic-bold-generated-protocol]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — wire discriminator (absorbs feature-session-isolation)

## Brief
The migrated session-isolation bugfix: required canonical `session_id` on every
chat-bearing ServerMessage (`user_message`, `agent_chunk`, `agent_done`,
`session_history`, `queued_message_state`, tool surfaces), fail-closed
validation at every receiver. This is the **absorption** of
`feature-session-isolation-wire-discriminator` — that feature's brief, root
cause, and diagnosis become this feature's bugfix slice. It lands as a child of
the canonical-session epic rather than a parallel track, and it depends on the
generated-protocol epic (the `session_id` field is generated, not hand-added).

Strategic decisions inherited from the absorbed feature: canonical `session_id`
(not room reuse); required + fail-closed (clean-room posture); absorb
`relay-cross-pc-room-targeting` as the relay half.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: the bugfix slice of the reconception — first user-visible win,
  lands before the full identity model reshapes every consumer.

## Foundation references
- Absorbed: `feature-session-isolation-wire-discriminator` (brief, root cause,
  reproduction) and `relay-cross-pc-room-targeting`.
- Evidence: `pi-extension/src/protocol/types.ts:93-154` (no discriminator),
  `app/lib/data/sync/sync_service.dart:671-760` (`_applyHistory` replaces box),
  `app/lib/data/transport/ws_transport.dart:63-103` (legacy fail-open),
  `relay/src/handlers/pi_forward.rs:128-173` + `relay/src/peers/registry.rs:369-384`
  (cross-PC fanout).

<!-- /agile-workflow:refactor-design fills in the field shape, validation sites,
and the cross-language contract test. -->
