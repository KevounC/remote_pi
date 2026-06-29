---
id: story-adversarial-findings-dedup-routing
kind: story
stage: done
tags: [app, pi-extension, relay, cockpit, workflow]
parent: feature-adversarial-codebase-review
depends_on: [story-adversarial-state-protocol-review, story-adversarial-mobile-lifecycle-review, story-adversarial-security-privacy-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Deduplicate adversarial findings and route work

Merge, verify, and route findings from the three reviewer passes for `feature-adversarial-codebase-review`.

## Scope

- Merge reviewer outputs.
- Directly verify each high/medium finding against code/docs.
- Mark false positives or uncertain findings.
- Convert concrete accepted issues into child `.work/active/stories/` or `.work/backlog/` items under `epic-remote-session-resilience-refactor` as appropriate.
- Update `feature-adversarial-codebase-review` with a final review summary and recommendation on narrow patches vs broader app/pi-extension refactor.

## Acceptance Criteria

- [x] Every accepted finding has evidence, failure scenario, severity, confidence, and routing.
- [x] Duplicate findings across reviewers collapse into one canonical item.
- [x] Unverified or low-confidence findings are labeled rather than filed as bugs.
- [x] The feature body records whether to patch narrowly or proceed with larger state-machine refactors.

## Dedup / routing result — 2026-06-28

Consumed reviewer outputs from:

- `story-adversarial-state-protocol-review`
- `story-adversarial-mobile-lifecycle-review`
- `story-adversarial-security-privacy-review`

Direct verification was performed with targeted `rg` and file reads over the implicated source/docs. The following outcomes were recorded in the parent feature's final summary.

## Accepted active stories

- `story-fix-late-attach-turn-stream-sync`
- `story-implement-extension-queued-message-protocol`
- `story-fix-cross-pc-transport-error-uuid`
- `story-fix-room-switch-snapshot-adoption`
- `story-fix-mobile-working-convergence-on-disconnect`
- `story-add-mobile-resume-hydration`
- `story-close-rooms-controller-on-dispose`
- `story-add-transport-frame-observability`
- `story-guard-stale-session-history-after-new`
- `story-fix-security-doc-drift`
- `story-reverify-relay-mesh-auth-cache`
- `story-harden-peers-json-permissions`
- `story-cap-relay-control-frame-fanout`

All active fix stories are parented to `epic-remote-session-resilience-refactor` and depend on `feature-adversarial-codebase-review` so they unlock after this review gate completes.

## Parked follow-up ideas

- `relay-cross-pc-room-targeting`
- `relay-pi-key-clone-detection`
- `relay-revocation-cache-window`
- `relay-mutex-poison-recovery`
- `app-owner-key-version-rollback-hardening`
- `workflow-ci-dependency-audit-gates`

## False-positive / adjusted findings

- The security reviewer claimed a stale root `README.md` E2E sentence. Direct grep found root README currently states the payload is **not** end-to-end encrypted. The root README still uses potentially confusing "opaque ciphertext" wording, so clarification is included in `story-fix-security-doc-drift`, but it is not treated as a direct E2E overclaim.

## Recommendation

Patch narrowly first. The high-confidence findings are concrete enough for focused stories with regression tests. Larger protocol/refactor directions remain parked until the patch set clarifies what state-machine shape remains.

## Review (2026-06-28)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review. Acceptance is complete; the three depended-on adversarial reviewer stories are done; all accepted active story ids and parked backlog ids exist; parent feature contains the final summary and narrow-patch recommendation.
