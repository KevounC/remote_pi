---
id: epic-bold-cockpit-workspace-projection-settings-split
kind: feature
stage: drafting
tags: [refactor, bold, cockpit]
parent: epic-bold-cockpit-workspace-projection
depends_on: [epic-bold-cockpit-workspace-projection-workspace-document]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Cockpit workspace — settings_page split

## Brief
`settings_page.dart` (3353 lines) is a whole settings application in one file.
Make it a route shell; each category (appearance, connectivity, daemons,
scheduling) owns its state/dialogs. The file's own `_Category` enum
(`settings_page.dart:40`) already sketches the natural seams.

## Epic context
- Parent epic: `epic-bold-cockpit-workspace-projection`
- Position: consumer of `workspace-document` (insofar as settings touches
  workspace config). Lowest-risk child; mostly mechanical split.

## Foundation references
- Evidence: `cockpit/lib/app/settings/ui/settings_page.dart:40`, `:878`,
  `:1187`, `:1717`, `:2593` (each category is already a mini-feature panel).

<!-- /agile-workflow:refactor-design pins the per-category split. -->
