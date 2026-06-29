---
id: epic-bold-transcript-event-log-projection-derive
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app, cockpit]
parent: epic-bold-transcript-event-log
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Transcript event log — projection derive (riskiest — design first)

## Brief
Streaming, mobile Hive rows, cockpit entries, and `session_sync` all derive
from the `TranscriptEvent` log. The riskiest part: reconciling optimistic local
sends (pending Hive row + send_timeout watchdog) with server-authoritative
events — the rule that keeps the user's just-sent message visible while
correctly folding in the authoritative transcript. This feature must prove that
reconcile rule before the store and hydration-replay children commit to it.

## Epic context
- Parent epic: `epic-bold-transcript-event-log`
- Position: riskiest child — the projection/reconcile rule is what the rest
  hangs on. Design FIRST.

## Foundation references
- Evidence of the three reducers: pi-extension `_messageBuffer`
  (`pi-extension/src/index.ts:1446-1470`, `:3538`); app `_applyHistory`
  (`app/lib/data/sync/sync_service.dart:671-760`); cockpit `_onEvent`
  (`cockpit/lib/app/cockpit/ui/session/agent_session.dart:436`); optimistic send
  (`app/lib/data/sync/sync_service.dart:170-263`).

<!-- /agile-workflow:refactor-design pins the projection + reconcile rule. -->
