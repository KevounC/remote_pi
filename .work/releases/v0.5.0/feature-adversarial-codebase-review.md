---
id: feature-adversarial-codebase-review
kind: feature
stage: done
tags: [app, pi-extension, relay, cockpit, workflow]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-mobile-remote-coding-best-practices-skill]
release_binding: v0.5.0
gate_origin: null
created: 2026-06-27
updated: 2026-06-28
---

# Multi-model adversarial codebase review

Run a broad, adversarial review of the Remote Pi fork before large refactors. Use multiple model families and independent passes so findings are less likely to share the same blind spots.

## Scope

- `pi-extension/` — Pi extension session lifecycle, mesh registration, message/event publication, room metadata, `/new` and reconnect behavior.
- `app/` — Flutter mobile state model, websocket/relay handling, rendering of connected/working/idle/error states, reconnect hydration.
- `relay/` — Rust relay routing, delivery guarantees, stale peer/session behavior, error signaling.
- `cockpit/` and `site/` only where they interact with shared protocol assumptions or operator documentation.

## Review shape

- At least two independent reviewer passes with different models.
- One pass biased toward state-machine/protocol correctness.
- One pass biased toward mobile lifecycle/UX failure modes.
- Optional third pass biased toward security/privacy and relay abuse cases.
- Orchestrator deduplicates findings, verifies claims against code, and files implementation items.

## Draft acceptance

- Findings are evidence-backed with file paths and failure scenarios.
- False positives are filtered or labeled uncertain.
- Concrete issues are converted into `.work/` stories/features under this epic.
- Review explicitly informs whether to patch narrowly or proceed with larger app/pi-extension refactors.

## Initial repo-eval pass — 2026-06-28

Report: `REPO-EVAL.md`.

Overall score: **6.1/10**. The initial holistic pass found a codebase with strong local test assets and unusually good agent/reference docs, but with material review targets before the adversarial pass:

- **No routine CI test gate**: GitHub Actions are release-oriented (`app-release`, `cockpit-release`) and do not run the documented subproject lint/test/build matrix on normal pushes/PRs.
- **Cross-language protocol drift risk**: message and room/action contracts are hand-mirrored across `pi-extension/src/protocol/types.ts`, `app/lib/protocol/protocol.dart`, and relay JSON/control-frame handling; no schema/generator or full conformance suite was found.
- **Stale security documentation**: `site/README.md` and `pi-extension/README.md` still contain E2E claims that contradict `PROTOCOL.md`; `pi-extension/CLAUDE.md` still references `libsodium-wrappers` after the E2E rollback.
- **App transport observability gap**: malformed/dropped frames and reconnect/parser failures can be swallowed by broad/silent catches in the Dart transport path, reducing diagnosability for mobile lifecycle failures.
- **Large convergence files**: `pi-extension/src/index.ts`, `app/lib/protocol/protocol.dart`, and cockpit viewmodel/widget files concentrate many responsibilities and should be focal points for review/refactor triage.

Use this as the baseline for the later multi-model adversarial review. Do not treat all repo-eval concerns as verified implementation stories yet; the adversarial pass should verify, deduplicate, and convert concrete failures into child stories/features under this epic.

## Architectural choice

Run the adversarial review as three independent read-only reviewer passes followed by one orchestrator-owned verification/dedup pass. This fits the feature better than a single monolithic scan because the highest-risk Remote Pi failures sit at different boundaries: app/extension/relay state convergence, mobile lifecycle UX, and relay/security/privacy. Keeping reviewer outputs independent preserves model diversity and reduces shared blind spots; the final orchestrator pass is the only step allowed to convert findings into `.work/` items.

Rejected alternatives:

- **One broad scanner pass**: faster, but too likely to blur protocol, mobile lifecycle, and security concerns into generic findings.
- **Immediate bug story creation from `REPO-EVAL.md`**: rejected because repo-eval findings are baseline risk signals, not verified adversarial failures.
- **Code changes during review**: rejected; this feature is an evidence-gathering and routing gate before invasive refactors.

## Implementation Units

### Unit 1: State-machine/protocol correctness review

**Story**: `story-adversarial-state-protocol-review`

**Review focus**:
- `PROTOCOL.md`, `pi-extension/src/protocol/`, `pi-extension/src/session/`, `pi-extension/src/transport/`, `relay/src/handlers/`, `relay/src/peers/`, `relay/src/rooms.rs`, and `app/lib/protocol/` / `app/lib/data/transport/`.
- Failure modes around `/new`, session replacement, stale SDK contexts, room metadata, queued messages, ACK/delivery semantics, reconnect hydration, late attach, dropped or duplicated turn state, and cross-PC envelope forwarding.

**Finding schema**:

```markdown
### <short title>
- **Severity**: critical|high|medium|low
- **Confidence**: high|medium|low
- **Evidence**: `path:line` plus quoted/summarized code behavior
- **Failure scenario**: concrete event sequence that breaks user-visible or protocol behavior
- **Suggested routing**: patch|refactor|test-only|uncertain
```

**Acceptance Criteria**:
- [x] Findings cite file paths and failure scenarios, not generic smells.
- [x] Review explicitly distinguishes verified bugs from uncertain risks.
- [x] Review calls out any assumptions that need orchestrator verification.

### Unit 2: Mobile lifecycle / UX failure-mode review

**Story**: `story-adversarial-mobile-lifecycle-review`

**Review focus**:
- `app/lib/data/transport/`, `app/lib/data/sync/`, `app/lib/ui/`, pairing/storage, app routing/viewmodels, and `mobile-remote-coding` checklist concerns.
- Failure modes around mobile background/resume, reconnect/offline loops, stale cached room/session state, `working`/idle rendering, multi-client state convergence, image/voice/queued-message UX, mounted guards, and silent transport errors.

**Finding schema**: same as Unit 1.

**Acceptance Criteria**:
- [x] Findings include user-visible symptoms on phone/tablet, not only code locations.
- [x] Review identifies whether each issue is app-only, extension-triggered, relay-triggered, or cross-boundary.
- [x] Review calls out missing deterministic tests/smokes for accepted risks.

### Unit 3: Security/privacy and relay abuse review

**Story**: `story-adversarial-security-privacy-review`

**Review focus**:
- `PROTOCOL.md` trust model, relay auth/mesh membership, pi-extension pairing/key storage, cross-PC anti-spoofing, documentation claims, and dependency/audit posture.
- Failure modes around spoofed peers, replay/rollback, malformed frames, relay-visible plaintext, stale E2E claims, clone handling, keyring fallback, self-revoke, and abuse of relay routing/control frames.

**Finding schema**: same as Unit 1.

**Acceptance Criteria**:
- [x] Review separates documentation/security-copy findings from exploitable code findings.
- [x] Review avoids claiming E2E protections that `PROTOCOL.md` explicitly rejects.
- [x] Review labels threat-model assumptions and required operator decisions.

### Unit 4: Orchestrator verification, dedup, and routing

**Story**: `story-adversarial-findings-dedup-routing`

**Depends on**: Units 1–3.

**Scope**:
- Merge reviewer outputs.
- Directly verify each high/medium finding against code/docs.
- Mark false positives or uncertain findings.
- Convert concrete accepted issues into child `.work/active/stories/` or `.work/backlog/` items under `epic-remote-session-resilience-refactor` as appropriate.
- Update this feature with a final review summary and recommendation on narrow patches vs broader app/pi-extension refactor.

**Acceptance Criteria**:
- [x] Every accepted finding has evidence, failure scenario, severity, confidence, and routing.
- [x] Duplicate findings across reviewers collapse into one canonical item.
- [x] Unverified or low-confidence findings are labeled rather than filed as bugs.
- [x] The feature body records whether to patch narrowly or proceed with larger state-machine refactors.

## Implementation Order

1. `story-adversarial-state-protocol-review` — independent reviewer pass.
2. `story-adversarial-mobile-lifecycle-review` — independent reviewer pass.
3. `story-adversarial-security-privacy-review` — independent reviewer pass.
4. `story-adversarial-findings-dedup-routing` — depends on all reviewer passes.

## Testing / verification approach

This feature is a review gate, so verification is evidence validation rather than code tests:

- Reviewer agents must be read-only and cite concrete files/line ranges.
- Orchestrator verifies important claims with direct reads/grep before filing work.
- If a finding needs reproduction, file a reproduction/test story rather than asserting a bug from static inspection alone.
- When converted to implementation work, lifecycle findings should prefer deterministic tests over sleeps and should cover success, error, abort, reconnect, shutdown, and session replacement where relevant.

## Risks

- **False positives from static review**: mitigated by the final verification/dedup story.
- **Shared blind spots despite multi-model review**: mitigated by distinct prompts and model families for the three reviewer passes.
- **Review scope ballooning into implementation**: mitigated by keeping code changes out of reviewer stories and routing accepted fixes into separate items.

## Final adversarial review summary — 2026-06-28

Three independent read-only reviewer passes completed and were recorded in:

- `story-adversarial-state-protocol-review`
- `story-adversarial-mobile-lifecycle-review`
- `story-adversarial-security-privacy-review`

The orchestrator verified the high/medium findings with direct reads/grep before routing. One claimed root `README.md` E2E stale sentence was not accepted as stated: root README currently says the payload is **not** end-to-end encrypted, though the "opaque ciphertext" wording is still slated for clarification.

### Accepted active follow-up stories

- `story-fix-late-attach-turn-stream-sync` — late mobile attach can miss a local/RPC turn reply.
- `story-implement-extension-queued-message-protocol` — app exposes queued messages but Pi extension ignores them.
- `story-fix-cross-pc-transport-error-uuid` — relay transport-error envelope ids are not UUID-shaped and can be dropped locally.
- `story-fix-room-switch-snapshot-adoption` — room snapshot can undo explicit same-peer room switch.
- `story-fix-mobile-working-convergence-on-disconnect` — chat-local working/streaming state sticks after relay disconnect mid-turn.
- `story-add-mobile-resume-hydration` — foreground resume lacks explicit room/session/WS hydration.
- `story-close-rooms-controller-on-dispose` — `ConnectionManager` does not close `_roomsController`.
- `story-add-transport-frame-observability` — malformed/unknown app frames need release-safe observability.
- `story-guard-stale-session-history-after-new` — stale session history can race app-triggered New Session.
- `story-fix-security-doc-drift` — stale E2E/libsodium/busy-protocol docs need alignment.
- `story-reverify-relay-mesh-auth-cache` — relay cross-PC auth cache must not trust stored blobs without signature verification.
- `story-harden-peers-json-permissions` — `peers.json` should be written with private permissions.
- `story-cap-relay-control-frame-fanout` — relay presence/rooms control frames need size/rate bounds.

### Parked follow-up ideas

Parked in `.work/backlog/` because they are larger, lower-confidence, or policy-bearing:

- `relay-cross-pc-room-targeting`
- `relay-pi-key-clone-detection`
- `relay-revocation-cache-window`
- `relay-mutex-poison-recovery`
- `app-owner-key-version-rollback-hardening`
- `workflow-ci-dependency-audit-gates`

### Refactor recommendation

Proceed with **narrow patches first** for the high-confidence correctness/security bugs above, especially queued messages, late attach, cross-PC transport errors, mobile disconnect convergence, resume hydration, and relay mesh-auth re-verification. Defer larger architectural refactors (cross-PC room-targeting, clone detection, revocation windows, generated protocol contracts) until the narrow patches are green and their tests expose any remaining state-machine shape problems.

### Reviewer provenance note

The original three adversarial reviewer story bodies preserved subagent IDs and read-only attestations, but did not preserve the exact model identifiers used by those reviewer passes. Final feature review treated that as a provenance gap and performed two fresh-context review passes with different model classes (`umans/umans-glm-5.2` for completeness and `openai-codex/gpt-5.5` for adversarial readiness) before advancing. Future multi-model review gates should record reviewer model identifiers directly in each reviewer story so model-family diversity remains auditable after subagent records expire.

## Review (2026-06-28)

**Verdict**: Approve with comments

**Blockers**: none
**Important**: none after inline provenance note
**Nits**: downstream `story-add-transport-frame-observability` remains intentionally `stage: drafting` for design-scope observability work; adjacent late-attach bridge work appears distinct but should be kept in mind during epic implementation.

**Notes**: Substrate deep feature review. Phase 1 completeness pass used fresh-context `umans/umans-glm-5.2` and found the review gate ready; Phase 2 adversarial pass used fresh-context `openai-codex/gpt-5.5` and found one important provenance gap. The provenance gap is recorded above because the expired original subagent records cannot be reconstructed. No routing blockers remain: all four child stories are done, accepted active follow-up stories and parked backlog ideas exist, and the feature records the narrow-patch recommendation.
