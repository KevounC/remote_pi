---
id: epic-bold-transcript-event-log-store
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app]
parent: epic-bold-transcript-event-log
depends_on: [epic-bold-transcript-event-log-projection-derive]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Transcript event log — append-only store

## Brief
Append-only `TranscriptEvent` store per session — pi-extension as source of
truth (`_messageBuffer` becomes an event log), app as local log (Hive can store
events; today it stores materialized rows). Scoped per session (depends on
`epic-bold-canonical-session`).

## Epic context
- Parent epic: `epic-bold-transcript-event-log`
- Position: consumer of `projection-derive`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:406-424`, `:1446-1470`;
  `app/lib/data/local/boxes.dart:1-68`.

<!-- /agile-workflow:refactor-design pins the store + retention. -->
