---
id: epic-bold-turn-state-machine-projection-consumers
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: epic-bold-turn-state-machine
depends_on: [epic-bold-turn-state-machine-algebraic-state]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Turn — projection consumers

## Brief
Every consumer of working/turn state becomes a projection of the canonical
`Turn` transition events: pi-extension broadcast (`_broadcastToActive` of
`agent_chunk`/`agent_done`), app working pill (`SyncService._working` /
`_workingReplyTo`), relay `room_meta.working` (merge-patch at
`relay/src/handlers/peer.rs:386-407`), cockpit `AgentStatus`. The "three
loosely-coupled signals converging on `working`" bug class
(`story-mobile-working-status-stuck`) is structurally eliminated — there's one
source.

## Epic context
- Parent epic: `epic-bold-turn-state-machine`
- Position: consumer of `algebraic-state`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:1506-1518` (publishes room meta on turn
  start/end), `app/lib/data/sync/sync_service.dart:960-968` (app local
  correction), `relay/src/handlers/peer.rs:386-407` (relay merge-patch),
  `cockpit/lib/app/cockpit/ui/session/agent_session.dart:1-140`.

<!-- /agile-workflow:refactor-design pins each consumer's projection. -->
