---
id: epic-bold-cockpit-workspace-projection-workspace-document
kind: feature
stage: drafting
tags: [refactor, bold, cockpit]
parent: epic-bold-cockpit-workspace-projection
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Cockpit workspace — workspace as document (riskiest — design first)

## Brief
Workspace state as a pure document + command set: project selection, pane-tree
layout, live process refs, persisted layout. `CockpitViewModel` (1982 lines,
~20 mutable fields) becomes a thin projection; process/file/git/LSP adapters
subscribe around it. The riskiest part is the pane-tree surgery
(`cockpit_viewmodel.dart:1009-1153`, tab move/split/index) — that intricate
layout logic must become pure-document operations before the rest of the
projection can hang off it.

## Epic context
- Parent epic: `epic-bold-cockpit-workspace-projection`
- Position: riskiest child — the document shape is what the rest hangs on.
  Design FIRST.

## Foundation references
- Evidence: `cockpit/lib/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart:51-140`,
  `:259-374` (`openFile`), `:1009-1153` (pane-tree surgery), `:1489-1580`
  (project activation/restoration).

<!-- /agile-workflow:refactor-design pins the document + command set. -->
