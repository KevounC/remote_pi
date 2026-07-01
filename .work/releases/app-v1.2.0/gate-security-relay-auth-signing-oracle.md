---
id: gate-security-relay-auth-signing-oracle
kind: story
stage: done
tags: [security]
parent: null
depends_on: []
release_binding: app-v1.2.0
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Relay auth signs attacker-controlled challenges with the owner key

## Severity
High

## Location
app/lib/data/transport/ws_transport.dart:184

## Issue
The app signs the relay-provided nonce directly with the long-term Ed25519 key, creating a cross-protocol signing oracle when production passes the owner key.

## Recommendation
Domain-separate relay-auth signatures with a fixed prefix/context and validate nonce length/randomness, or use a separate relay-auth key.
