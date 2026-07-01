---
id: gate-cruft-temp-debug-trace-scaffold
kind: story
stage: drafting
tags: [cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-01
---

# Temporary debug trace scaffold remains in production UI flow

## Location
cockpit/lib/app/cockpit/ui/widgets/workspace_settings_dialog.dart:9

## Issue
The file contains a DEBUG temporario trace helper (_trace writing ck_trace.log) plus callsites that are still active, which looks like temporary diagnostics left in production and can leave persistent temp-file side effects.

## Recommendation
Remove the temporary tracing helper and its callsites (or guard them with kDebugMode) so debug-only instrumentation is not shipped in the normal path.
