---
id: epic-bold-transcript-event-log-hydration-replay
kind: feature
stage: drafting
tags: [refactor, bold, app, pi-extension]
parent: epic-bold-transcript-event-log
depends_on: [epic-bold-transcript-event-log-store]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Transcript event log — hydration as replay, not replace

## Brief
`_applyHistory` (`app/lib/data/sync/sync_service.dart:671-760`) stops being a
replace operation and becomes a replay over the event log. A foreign
`session_history` can't overwrite the local transcript because the projection is
recomputed from the local event log — the direct structural fix for "session B
showed only session A's stray turn and none of its own." Session-scoped: a
foreign `session_id` is already rejected by
`epic-bold-canonical-session-app-attribution-hydration`; this feature makes the
box itself tamper-proof by derivation.

## Epic context
- Parent epic: `epic-bold-transcript-event-log`
- Position: consumer of `store`.

## Foundation references
- Evidence: `app/lib/data/sync/sync_service.dart:671-760`, `:762-...`
  (`_convertHistory`).

<!-- /agile-workflow:refactor-design pins the replay semantics. -->
