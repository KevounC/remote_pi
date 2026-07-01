---
id: gate-cruft-empty-catch-formatter-reload
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

# Empty catch-swallow in formatter reload path

## Location
cockpit/lib/app/cockpit/ui/widgets/file_viewer.dart:368

## Issue
_reloadFromDisk silently ignores all exceptions from readAsString() with an empty catch, masking formatter/read failures and making recovery/debugging harder.

## Recommendation
At minimum log or surface a non-invasive error signal (e.g., debug/info telemetry) when reload fails, while preserving current fallback behavior.
