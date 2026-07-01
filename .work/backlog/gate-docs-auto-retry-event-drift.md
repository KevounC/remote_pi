---
id: gate-docs-auto-retry-event-drift
kind: story
stage: drafting
tags: [documentation]
parent: null
depends_on: []
release_binding: null
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# Inconsistent treatment of auto_retry_* events in protocol doc

## Location
cockpit/docs/rpc-protocol.md:170-175 ; cockpit/lib/app/cockpit/data/adapters/rpc_event_mapper.dart:68-74

## Issue
The doc lists auto_retry_* as ignored events, but implementation parses auto_retry_start into RpcAutoRetry and renders retry messaging in UI flow.

## Recommendation
Remove auto_retry_* from the ignored-event list and keep only truly ignored event families listed.
