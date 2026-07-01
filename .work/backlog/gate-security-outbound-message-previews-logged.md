---
id: gate-security-outbound-message-previews-logged
kind: story
stage: drafting
tags: [security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Outbound message previews are written to logs

## Severity
Low

## Location
app/lib/data/sync/sync_service.dart:260

## Issue
debugPrint logs up to 80 characters of user message text, which can expose prompts or secrets through device logs.

## Recommendation
Log only message IDs/metadata, redact message bodies, and guard diagnostic logging behind debug-only flags.
