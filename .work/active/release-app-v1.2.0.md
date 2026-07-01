---
id: release-app-v1.2.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: app-v1.2.0
gate_origin: null
created: 2026-07-01
updated: 2026-07-01
---

# Release app-v1.2.0

Second gate-enabled release. Binds the app-attributed (mobile) bold-refactor work:
canonical-session attribution/hydration, reachability-contract app adapter +
state-machine, transcript event log (store/hydration-replay/projection-derive).
2 parent features ship whole; 4 stories' parents are multi-component (route to
repo-level v0.6.0) — phased delivery, informational under epic_cohesion: phased.

## Bound items

### Active done items (12)
- epic-bold-canonical-session-app-attribution-hydration (feature — app-only, ships whole)
- epic-bold-reachability-contract-app-adapter (feature — app-only, ships whole)
- epic-bold-reachability-contract-app-adapter-step-1..3 (3 stories — parent is app-only)
- epic-bold-reachability-contract-state-machine-step-3 (story — parent is repo-level)
- epic-bold-transcript-event-log-hydration-replay-step-1..2 (2 stories — parent is repo-level)
- epic-bold-transcript-event-log-projection-derive-step-2..3 (2 stories — parent is repo-level)
- epic-bold-transcript-event-log-store-step-1..2 (2 stories — parent is repo-level)

### Archived stubs late-bound
(none — unbound archived stubs are all multi-component → repo-level)

## Gate runs

### gate-cruft (2026-07-01) — 5 findings (0 high, 2 medium, 3 low)

- Medium: room-adoption persistence failures dropped (connection_manager.dart:1117)
- Medium: _enqueue drops write-chain exceptions (sync_service.dart:1263)
- Low: silent dynamic setActiveRoom fallback (connection_manager.dart:272), empty catch old-channel close (:431), legacy sync/turn compat shims (sync_service.dart:129-134 + transcript_projection.dart:7)
5 items → backlog (all non-blocking). Scanner survived (1 compaction, returned clean output — app bundle ~19 files under the compaction threshold).

### gate-tests (2026-07-01) — 1 gap (0 critical, 0 high, 1 medium) from 75 ACs (74 covered)

- Medium: LocalBoxes.init restart preservation only partially covered (proves runtime wiped, not that sessions_index preserved across restart)
1 item → backlog (non-blocking). Bundle had strong existing test coverage (most ACs already covered).

(populated by remaining gates as they complete)

### gate-security (2026-07-01) — 4 findings (0 critical, 1 high, 2 medium, 1 low)

- **High (blocking)**: relay auth signs attacker-controlled nonce with long-term owner Ed25519 key — cross-protocol signing oracle (ws_transport.dart:184)
- Medium: transcript Hive box names can collide after _safe sanitization (boxes.dart:98)
- Medium: durable transcript boxes unencrypted (boxes.dart:77)
- Low: outbound message previews logged (sync_service.dart:260)
1 high bound (implementing, blocking); 3 med/low → backlog.

### gate-patterns (2026-07-01) — 4 pattern candidates discovered

4 reusable shapes (3+ occurrences each): immutable-Hive-record-DTO-triad, incremental-Hive-projection-streams, transcript-pipeline-replay→projection→materialized-rows, reachability-as-explicit-state-machine. Pattern-skill authoring deferred (separate artifact under .agents/skills/patterns/). Recorded for traceability.

### gate-docs (2026-07-01) — re-scanning (first scanner hit compaction, returned no output)

### Binding-consistency warnings

binding_guard=warn epic_cohesion=phased. CONFLICTS(6) + INCOMPLETES(4), all
informational/non-halting — expected phased delivery where app-tagged stories ship
here while their multi-component parent features/epics ship in v0.6.0. Not true
orphans; same pattern as cockpit-v1.6.0.
