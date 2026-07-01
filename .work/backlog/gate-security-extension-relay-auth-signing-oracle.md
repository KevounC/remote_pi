---
id: gate-security-extension-relay-auth-signing-oracle
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

# Pi extension relay auth signs attacker-controlled challenges with the owner key

## Severity
High

## Domain
Cryptography / Authentication & Authorization

## Location
`pi-extension/src/transport/relay_client.ts:238`

## Evidence
```ts
const nonce = Buffer.from((challenge as ChallengeMsg).nonce, "base64");
const sig = ed25519Sign(this.keypair.secretKey, nonce);
```

## Issue
Relay authentication signs the relay-provided nonce bytes directly with the Pi extension's long-term Ed25519 secret key. The challenge is only checked for presence, not decoded length/shape, freshness, or a protocol/domain prefix. A malicious relay can therefore use the extension as a signing oracle for arbitrary Ed25519 messages under the long-term identity key, which is dangerous if the key is reused across mesh membership or future protocol signatures.

## Remediation direction
Domain-separate relay-auth signatures with a fixed context/prefix and version, validate the decoded challenge length and encoding before signing, and consider using a dedicated relay-auth key rather than the long-term mesh/identity key.
