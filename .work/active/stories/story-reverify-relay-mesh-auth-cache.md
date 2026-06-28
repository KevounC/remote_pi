---
id: story-reverify-relay-mesh-auth-cache
kind: story
stage: implementing
tags: [relay, security, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Re-verify mesh signatures in relay cross-PC auth cache

Relay `MeshAuthCache::members_of()` authorizes cross-PC forwarding by parsing stored mesh blobs without re-verifying their Owner signatures. Write-path verification is not enough if the relay DB is corrupted or modified out-of-band.

## Acceptance Criteria

- [ ] Mesh auth cache read path verifies Owner signature and owner hash before trusting members.
- [ ] Invalid/corrupt stored blobs are skipped and logged without authorizing forwarding.
- [ ] Add relay tests proving an invalid stored blob cannot authorize `pi_envelope` forwarding.
