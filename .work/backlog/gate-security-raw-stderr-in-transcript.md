---
id: gate-security-raw-stderr-in-transcript
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Raw child stderr is surfaced directly in the transcript

## Location
cockpit/lib/app/cockpit/ui/session/agent_session.dart:658

## Issue
Stderr from the spawned Pi process is displayed verbatim as a transcript side-channel, which can expose provider errors, local paths, or accidental secrets.

## Recommendation
Redact common secret patterns and/or show a generic diagnostic with a separate explicit copy raw details path for local troubleshooting.
