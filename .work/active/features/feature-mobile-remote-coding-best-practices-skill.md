---
id: feature-mobile-remote-coding-best-practices-skill
kind: feature
stage: drafting
tags: [app, pi-extension, relay, workflow]
parent: epic-remote-session-resilience-refactor
depends_on: []
created: 2026-06-27
updated: 2026-06-27
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

## Draft acceptance

- Research cites current authoritative sources for Flutter/mobile lifecycle and networking behavior where training data may be stale.
- Skill/checklist is specific to Remote Pi's relay/mesh/remote-coding architecture, not generic Flutter advice.
- The stale `Working` bug and `/new` multi-client semantics are covered explicitly.
