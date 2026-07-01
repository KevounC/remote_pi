---
id: gate-security-relay-owner-messages-unsigned
kind: story
stage: implementing
tags: [security]
parent: null
depends_on: []
release_binding: null
gate_origin: security
created: 2026-07-01
updated: 2026-07-01
---

# Relay-routed owner messages lack end-to-end authentication

## Severity
High

## Domain
Authentication & Authorization / Cryptography / Data Protection

## Location
`pi-extension/src/transport/peer_channel.ts:67`

## Evidence
```ts
const ct = Buffer.from(JSON.stringify(msg)).toString("base64");
const outer: OuterEnvelope = { peer: this.remotePeerId, ct };
```

Additional ingress evidence: `pi-extension/src/extension/owner_multiplexer.ts:244` trusts `outer.peer` for known-owner reattachment, and `pi-extension/src/transport/peer_channel.ts:111` decodes `outer.ct` without a message signature or MAC.

## Issue
The app↔Pi owner data plane wraps JSON as base64 only. Once an owner is paired, the Pi accepts messages routed with that owner's `peer` id and dispatches control actions such as `user_message`, `cancel`, `session_new`, `model_set`, and `thinking_set`. A compromised or malicious relay can read/alter plaintext frames or inject a forged `ct` under a known owner peer id, because the Pi verifies relay routing but not end-to-end message integrity from the owner key.

## Remediation direction
Add end-to-end integrity for owner data-plane frames: derive a per-pairing/session key or sign canonical inner messages with domain-separated context, verify before dispatch, and reject unsigned/failed frames. Prefer restoring an authenticated encrypted channel if transcript/tool data should remain hidden from the relay.
