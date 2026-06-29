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

## Absorbed from `story-mobile-working-status-stuck` (retired 2026-06-29)

The retired story's reproduction confirms the projection-consumer target: mobile
can continue showing `Working` after the Pi agent is idle. Suspected causes it
documented — all three are the "three loosely-coupled signals converging" the
algebraic turn state machine eliminates:
- Pi publishes `room_meta.working: true` on turn start but misses/loses the
  corresponding false on turn end, errors, session switch, compaction, or
  shutdown.
- Reconnect hydration replays cached `working: true` without authoritative idle
  correction.
- App-side room meta treats `working` as sticky and does not reconcile with
  connection/session lifecycle.

The projection-consumer design must cover all five turn-end paths (end, error,
session switch, compaction, shutdown) and the reconnect-hydration replay as
projection states, not ad-hoc corrections.

<!-- /agile-workflow:refactor-design pins each consumer's projection. -->
