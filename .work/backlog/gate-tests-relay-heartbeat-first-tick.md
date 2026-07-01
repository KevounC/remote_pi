---
id: gate-tests-relay-heartbeat-first-tick
kind: story
stage: drafting
tags: [testing]
parent: null
depends_on: []
release_binding: null
gate_origin: tests
created: 2026-07-01
updated: 2026-07-01
---

# Relay heartbeat first-tick timing has only partial test coverage

## Severity
Medium

## Location
relay/src/handlers/peer.rs:125

## Issue
AC uncovered (bound item: epic-bold-reachability-contract-state-machine-step-4): Relay behavior remains the same: first ping after 25s, then every 25s. Only partial coverage.

## Recommendation
Add a paused-time Tokio test or extract a heartbeat-construction helper to assert no immediate ping and the first/repeated ticks occur at RELAY_WS_PING_INTERVAL.
