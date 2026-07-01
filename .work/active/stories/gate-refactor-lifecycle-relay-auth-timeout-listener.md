---
id: gate-refactor-lifecycle-relay-auth-timeout-listener
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: extension-0.6.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Relay auth timeout leaves its challenge listener attached

## Library
lifecycle

## Rule
resource-no-dispose

## Confidence
High

## Location
`pi-extension/src/transport/relay_client.ts:253`

## Issue
`_nextMsg` clears the auth timeout on the success path, but the timeout path rejects without removing the `ws.once("message")` listener registered at line 257, leaving a stale listener on the WebSocket until a later message or socket teardown.

## Fix
Use named cleanup shared by the timeout and message paths: clear the timer, remove the pending message listener (and any close/error listener added for the wait), then resolve or reject exactly once.
