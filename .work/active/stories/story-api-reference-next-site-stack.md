---
id: story-api-reference-next-site-stack
kind: story
stage: drafting
tags: [research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
research_dials:
  scope_authority: mixed
  verification_rigor: floor
  intent: next-site-api-reference
  output_kind: skill-reference-or-deferral
created: 2026-06-27
updated: 2026-06-27
---

# API reference for Next/React site stack

Create or explicitly defer a lightweight platform-style reference for `site/`.

## Candidate coverage

- Next 16 app conventions used by this repo.
- React 19 patterns relevant to the site.
- Tailwind 4/PostCSS setup.
- TypeScript/ESLint commands and build cycle.
- Deployment/static-site assumptions if documented elsewhere.

## Deferral option

Because the current refactor arc is mostly app + pi-extension + relay, this may be a short deferral note rather than a full reference. If site work is not active, record the reason and the tripwire for creating the reference later.

## Acceptance

- Either a concise site stack reference exists and is linked, or the item records a clear deferral rationale.
- If authored, it uses current Next/React/Tailwind docs rather than stale assumptions.
