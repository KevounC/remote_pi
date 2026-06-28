---
id: feature-adversarial-codebase-review
kind: feature
stage: drafting
tags: [app, pi-extension, relay, cockpit, workflow]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-mobile-remote-coding-best-practices-skill]
created: 2026-06-27
updated: 2026-06-27
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
