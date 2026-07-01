---
id: gate-docs-claudemd-stale-mvp-constraints
kind: story
stage: drafting
tags: [documentation]
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# cockpit/CLAUDE.md still describes single-pane/MVP constraints that are no longer true

## Location
cockpit/CLAUDE.md:15-16 ; cockpit/lib/app/cockpit/domain/entities/workspace_document.dart:20-23 ; cockpit/lib/app/cockpit/ui/viewmodels/workspace_projection.dart:26-30 ; cockpit/lib/app/settings/ui/categories/connectivity_settings_panel.dart:77-213

## Issue
It states panes/multiplexation are not yet in place and implies no relay/crypto pair flow, but implementation now has pane documents (LeafPane/SplitPane), workspace projections for multiple sessions/tabs, and active connectivity/relay UI paths.

## Recommendation
Refresh CLAUDE scope/assumptions to current architecture (workspace-document projection, multi-pane workspace, relay/paired-device controls, control RPC surface).
