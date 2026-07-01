---
id: gate-refactor-protocol-session-scope-reenumeration
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Session scope helpers re-enumerate generated message type strings

## Library
protocol-contract

## Rule
discriminator-reenumerated

## Confidence
Medium

## Location
`pi-extension/src/protocol/session_scope.ts:3`

## Issue
`SESSION_SCOPED_SERVER_TYPES`, `NON_SESSION_SCOPED_SERVER_TYPES`, and `SESSION_SCOPED_CLIENT_TYPES` hand-list protocol discriminators already present in generated `SERVER_MESSAGE_TYPES` and `CLIENT_MESSAGE_TYPES`.

## Fix
needs analysis
