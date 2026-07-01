---
id: gate-cruft-enqueue-drops-write-errors
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

# _enqueue drops write-chain exceptions

## Severity
Medium

## Location
app/lib/data/sync/sync_service.dart:1263

## Issue
_writeChain = next.catchError((Object _, StackTrace _) {}); discards all write errors, masking persistence/event failures and removing end-user/developer observability.

## Recommendation
Report and classify errors in the catch path, then continue the chain intentionally (e.g., emit diagnostics and return a neutral state).
