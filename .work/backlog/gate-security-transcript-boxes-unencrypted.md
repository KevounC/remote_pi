---
id: gate-security-transcript-boxes-unencrypted
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

# Durable transcript data is stored in default Hive boxes

## Severity
Medium

## Location
app/lib/data/local/boxes.dart:77

## Issue
Transcript event logs are opened as default Hive boxes without an encryption cipher while they persist message text, images, tool args/results, and summaries.

## Recommendation
Encrypt durable transcript boxes with a key stored in platform secure storage, or explicitly gate/document plaintext local transcript retention.
