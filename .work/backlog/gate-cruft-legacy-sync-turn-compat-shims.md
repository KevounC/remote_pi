---
id: gate-cruft-legacy-sync-turn-compat-shims
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

# Legacy sync/turn compatibility wrappers remain in production surface

## Severity
Low

## Location
app/lib/data/sync/sync_service.dart:129-134 ; app/lib/domain/transcript/transcript_projection.dart:7

## Issue
SyncService compatibility getters (isWorking, workingStream, workingReplyTo) and TranscriptTurnStatus alias are transitional compatibility surfaces; keeping both increases API drift risk versus canonical projection types.

## Recommendation
Migrate callers to canonical projection APIs and remove these shims from production surface (or gate them as test-only utilities if still needed).
