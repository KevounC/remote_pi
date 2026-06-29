---
id: story-reverify-relay-mesh-auth-cache
kind: story
stage: done
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

- [x] Mesh auth cache read path verifies Owner signature and owner hash before trusting members.
- [x] Invalid/corrupt stored blobs are skipped and logged without authorizing forwarding.
- [x] Add relay tests proving an invalid stored blob cannot authorize `pi_envelope` forwarding.

## Implementation notes

- Files changed: `relay/src/handlers/pi_forward.rs`, `relay/src/mesh/store.rs`.
- Tests added: `MeshAuthCache` unit coverage for invalid signatures and owner-hash mismatches, plus `handle_pi_envelope` coverage proving corrupt stored blobs return `not_authorized` instead of authorizing forwarding.
- Discrepancies from design: none.
- Adjacent issues parked: none.
- Verification: `cd relay && cargo fmt --check && cargo clippy -- -D warnings && cargo test` passed.

## Review (2026-06-28)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fresh-context review of commit `8dc8bf3`; correctness, tests, security/privacy, mesh signature re-verification, design alignment, and foundation-doc drift lenses checked. Verification evidence from implementation notes accepted; tests were not re-run.
