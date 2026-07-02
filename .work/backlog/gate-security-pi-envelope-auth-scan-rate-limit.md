---
id: gate-security-pi-envelope-auth-scan-rate-limit
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

# Pi-envelope authorization scans mesh storage without a negative cache or per-frame limiter

## Severity
Medium

## Domain
API Security / Error Handling & Logging

## Location
`relay/src/handlers/pi_forward.rs:78`

## Evidence
```rust
let envelopes = match store.all_envelopes() {
    Ok(records) => records,
    Err(e) => {
        warn!("mesh store read failed during auth: {e}");
        return None;
```

## Issue
Every `pi_envelope` authorization miss can fall through to `store.all_envelopes()` and scan the persisted mesh blobs. The cache only stores positive membership sets; the source comment explicitly says negative lookups are not cached, and `relay/src/handlers/connection_actor.rs:170` dispatches `PiEnvelope` frames without the peer-cost limiter used for presence/rooms control checks. An authenticated but untrusted relay client can repeatedly send envelopes to arbitrary `to_pc` values and force repeated SQLite/blob-verification work. Provenance: pre-existing in the cross-PC forwarding implementation, but the touched `pi_forward`/connection actor files are in the v0.6.0 bundle and the issue is not already tracked by the existing security backlog items.

## Remediation direction
Bound the work per connection for `pi_envelope` authorization: add a small negative cache/TTL for absent source memberships and/or a per-window cost limiter for forwarding attempts, and invalidate/refresh cache entries on mesh publish events so authorization remains timely without allowing unbounded scan amplification.
