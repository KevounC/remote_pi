---
id: gate-cruft-empty-catch-old-channel-close
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

# Empty catch around old channel close during adopt

## Severity
Low

## Location
app/lib/data/transport/connection_manager.dart:431

## Issue
In adopt, exceptions from old.close() are fully swallowed (catch {}), so close failures are hidden and cannot be diagnosed even if resource teardown is incomplete.

## Recommendation
At minimum log/track close failures while keeping best-effort cleanup; avoid fully silent swallowing.
