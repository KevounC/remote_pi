---
id: epic-bold-transcript-event-log
kind: epic
stage: implementing
tags: [refactor, bold, pi-extension, app, cockpit]
parent: null
depends_on: [epic-bold-canonical-session]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Transcript is an append-only event log — every UI is a projection

## Thesis
`TranscriptEvent` is the canonical domain log per session. Live streaming,
mobile Hive rows, cockpit entries, and `session_sync` all *derive* from it.
Hydration becomes replay, not replace — you cannot overwrite a projection with
foreign state.

## Lens
Declarative

## Impact
The transcript exists as three separate reducers: pi-extension
`_messageBuffer` → `session_history` (`index.ts:1446-1470`, `3538`); app
`_applyHistory` which *replaces* Hive rows (`sync_service.dart:671-760`); cockpit
`AgentSession._onEvent` fold (`agent_session.dart:436`). The app's reducer
replaces state while the others append — that asymmetry is the direct cause of
"session B showed only session A's stray turn and none of its own": a foreign
`session_history` overwrote B's box. `TranscriptEvent` as the canonical log makes
every consumer a projection; `_applyHistory` stops being a replace and becomes a
replay, so a foreign history can't corrupt the local box because the projection
is recomputed from the local event log.

## Cost
Requires an append-only event store on the app side (Hive can do it; today it
stores materialized rows). Reconciling optimistic local sends with
server-authoritative events needs care — the riskiest child. Depends on
canonical-session (to scope the log per session). Easier after the
generated-protocol epic (events are generated wire types).

## Child features (riskiest first)
- **epic-bold-transcript-event-log-projection-derive** *(riskiest — design this
  first; reconciling optimistic local sends with server-authoritative events is
  the hard part the epic hangs on)* — streaming, Hive rows, cockpit entries, and
  `session_sync` all derive from the event log; the optimistic-send reconcile
  rule.
- epic-bold-transcript-event-log-store — append-only `TranscriptEvent` store per
  session (pi-extension source of truth + app local log).
- epic-bold-transcript-event-log-hydration-replay — `_applyHistory` becomes
  replay, not replace; foreign-history corruption structurally impossible.

## Decomposition

Decomposition pre-existed (bold-refactor scan) — child features listed above in "Child features (riskiest first". Advanced to implementing via epic-design Phase 1.5 short-circuit.
