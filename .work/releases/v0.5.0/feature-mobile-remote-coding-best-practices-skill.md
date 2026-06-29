---
id: feature-mobile-remote-coding-best-practices-skill
kind: feature
stage: done
tags: [app, pi-extension, relay, workflow, research, docs]
parent: epic-remote-session-resilience-refactor
depends_on: []
release_binding: v0.5.0
gate_origin: null
research_dials:
  scope_authority: mixed
  verification_rigor: standard
  intent: mobile-remote-coding-practices
  output_kind: skill-reference
created: 2026-06-27
updated: 2026-06-28
---

# Mobile remote-coding best-practices research + skill

Do a focused current-practice research pass before large mobile/extension refactors, then capture the results as a reusable local skill/checklist for Remote Pi work.

## Questions to answer

- Flutter mobile app lifecycle constraints for long-lived remote sessions: foreground/background, app suspension, push/local notifications, websocket reconnect, and state restoration.
- Reliable relay/mesh client semantics: authoritative state snapshots vs event deltas, sequence numbers, idempotency, reconnect hydration, and stale-cache prevention.
- UX expectations for remote coding control surfaces: explicit connected/working/idle/error states, multi-client synchronization, and safe handling of `/new` or session switches.
- Verification practices: deterministic state-machine tests, simulated disconnect/reconnect, dropped/duplicated/out-of-order events, and smoke scenarios across mobile + workstation.

## Expected output

- A concise research note or plan artifact summarizing current best practices and trade-offs.
- A reusable skill/checklist in the fork (location to choose during design) for future app/pi-extension changes.
- Follow-up implementation items for any concrete architecture changes uncovered.

## Implementation notes

- Added synthesis brief `.research/analysis/briefs/mobile-remote-coding-skill-base.md`.
- Added reusable checklist `.agents/skills/mobile-remote-coding/SKILL.md`.
- Added source attestations for mobile lifecycle/background networking, WebSocket behavior, Flutter app lifecycle, and Remote Pi local app transport state.
- Linked the checklist from `AGENTS.md` and `app/CLAUDE.md`.
- No immediate architecture follow-up item was emitted: the research confirmed the current intended direction (authoritative snapshots, idempotent commands, reconnect hydration, explicit stale/working/error states) rather than uncovering a new implementation slice beyond existing stuck-`Working` and session-resilience work.
- Verification: attestation-handle grep passed; ARD citation lint on the synthesis brief passed with `0 broken`; read-only reviewer subagent approved with no blockers.

## Acceptance

- [x] Research cites current authoritative sources for Flutter/mobile lifecycle and networking behavior where training data may be stale.
- [x] Skill/checklist is specific to Remote Pi's relay/mesh/remote-coding architecture, not generic Flutter advice.
- [x] The stale `Working` bug and `/new` multi-client semantics are covered explicitly.
