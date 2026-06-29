---
id: epic-bold-cockpit-workspace-projection-agent-session
kind: feature
stage: drafting
tags: [refactor, bold, cockpit]
parent: epic-bold-cockpit-workspace-projection
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document, epic-bold-transcript-event-log]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Cockpit workspace — AgentSession as transcript projection

## Brief
`AgentSession` (`agent_session.dart`) fuses transcript renderer + RPC process
lifecycle + controls + relay state + turn machine (`AgentStatus` +
`_pendingSend` + `_awaitingUserEcho` + `_turnStartedAt` + `_openText` +
`_openTools`). It becomes a projection of the transcript event log (depends on
`epic-bold-transcript-event-log`) and the canonical turn state
(depends on `epic-bold-turn-state-machine`). Retires the fused
turn/streaming/tool fold (`_onEvent`, `agent_session.dart:436`).

## Epic context
- Parent epic: `epic-bold-cockpit-workspace-projection`
- Position: consumer of `workspace-document` + the transcript event log.

## Foundation references
- Evidence: `cockpit/lib/app/cockpit/ui/session/agent_session.dart:15-140`,
  `:316-380` (`_populateTranscript`), `:436-...` (`_onEvent` switch).

<!-- /agile-workflow:refactor-design pins the projection + process lifecycle. -->
