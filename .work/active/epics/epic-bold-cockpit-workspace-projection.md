---
id: epic-bold-cockpit-workspace-projection
kind: epic
stage: done
tags: [refactor, bold, cockpit]
parent: null
depends_on: [epic-bold-generated-protocol]
release_binding: cockpit-v1.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Cockpit workspace is a document; the agent session is a projection

## Thesis
The desktop workspace is a pure document plus commands; `AgentSession` becomes a
projection of the transcript event log, not a reducer fused to a process owner.
The 1982-line `CockpitViewModel` and 3353-line `settings_page.dart` stop being
god objects.

## Lens
Inversion / Declarative

## Impact
`CockpitViewModel` (`cockpit_viewmodel.dart`, 1982 lines) is a desktop workspace
OS in one `ChangeNotifier`: project CRUD, worktree lifecycle, pane tree, tab
drag/drop, agent boot, terminal boot, file reload, git watching, LSP, layout
persistence, notifications — all over ~20 mutable fields (`_restoring`, `_ready`,
`_selectedProjectId`, `_trees`, `_sessions`, `_saveTimers`). `AgentSession`
(`agent_session.dart`) fuses transcript renderer + RPC process lifecycle +
controls + relay state + turn machine (`AgentStatus` + `_pendingSend` +
`_awaitingUserEcho` + `_turnStartedAt`). `settings_page.dart` (3353 lines) is a
whole settings application in one file. Make workspace a document + commands
with process/file/git/LSP adapters subscribing around it; make `AgentSession` a
projection of the transcript event log (depends on
`epic-bold-transcript-event-log`); make settings a route shell with per-category
features.

## Cost
Large but contained to `cockpit/`. Cockpit is internally the cleanest
ports/adapters example (`domain/contracts` + `data` adapters + module wiring),
so the seams exist — this epic extends them. `AgentSession`-as-projection depends
on the transcript-event-log epic landing (or a local transcript-event subset).
Hardest part: the pane-tree surgery (`cockpit_viewmodel.dart:1009-1153`) is
genuinely intricate layout logic.

## Child features (riskiest first)
- **epic-bold-cockpit-workspace-projection-workspace-document** *(riskiest —
  design this first; the pane-tree as a pure document is the intricate part the
  rest hangs on)* — workspace state as a document + command set; `CockpitViewModel`
  becomes a thin projection; process/file/git/LSP subscribe around it.
- epic-bold-cockpit-workspace-projection-agent-session — `AgentSession` becomes a
  transcript projection (depends on `epic-bold-transcript-event-log`); retires its
  fused turn/streaming/tool fold.
- epic-bold-cockpit-workspace-projection-settings-split — `settings_page.dart`
  becomes a route shell; each category (appearance, connectivity, daemons,
  scheduling) owns its state/dialogs.

## Decomposition

Decomposition pre-existed (bold-refactor scan) — child features listed above in "Child features (riskiest first". Advanced to implementing via epic-design Phase 1.5 short-circuit.
