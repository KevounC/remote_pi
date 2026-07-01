---
id: gate-security-transcript-box-name-collision
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

# Transcript Hive box names can collide after sanitization

## Severity
Medium

## Location
app/lib/data/local/boxes.dart:98

## Issue
_safe replaces unsafe characters with _ and collapses runs, so distinct room/session identifiers can map to the same transcript box name.

## Recommendation
Encode each key segment with a reversible safe encoding or a length-bounded hash, and avoid lossy replacement for storage identities.
