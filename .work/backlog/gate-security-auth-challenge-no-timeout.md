---
id: gate-security-auth-challenge-no-timeout
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

# Auth challenge step can be held open indefinitely

## Severity
Medium

## Location
relay/src/handlers/peer.rs:83

## Issue
After a valid hello, the relay waits on stream.next().await for auth without a timeout, so unauthenticated clients can hold pre-auth sockets/tasks open indefinitely.

## Recommendation
Add an auth-response timeout like HELLO_TIMEOUT_MS and close the socket if auth is not received promptly.
