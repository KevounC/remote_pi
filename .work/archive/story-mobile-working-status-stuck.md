---
id: story-mobile-working-status-stuck
kind: story
stage: drafting
tags: [pi-extension, app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: null
gate_origin: null
status: superseded
superseded_by: epic-bold-turn-state-machine-projection-consumers
created: 2026-06-27
updated: 2026-06-27
---

# Fix mobile `Working` status stuck true

Promoted implementation story for backlog bug `.work/backlog/remote-pi-mobile-working-status-stuck.md`.

## Observed behavior

Mobile can continue showing `Working` after the workstation/Pi agent is idle and not taking a turn.

## Suspected causes

- Pi extension publishes `room_meta.working: true` on turn start but misses/loses the corresponding false update on turn end, errors, session switch, compaction, or shutdown.
- Reconnect hydration replays cached `working: true` without authoritative idle correction.
- App-side room meta state treats `working` as sticky and does not reconcile with connection/session lifecycle.

## Draft acceptance

- Reproduction path documented.
- Fix makes working/idle state authoritative after normal turn end, error/abort, reconnect, and `/new` session switch.
- Tests or smoke checklist cover dropped event/reconnect scenarios.
- Mobile UI can distinguish `connected but idle` from `working`, `disconnected`, and `unknown/stale`.
