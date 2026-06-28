---
id: story-api-reference-next-site-stack
kind: story
stage: done
tags: [research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
research_refs: [next-site-skill-base]
research_dials:
  scope_authority: mixed
  verification_rigor: floor
  intent: next-site-api-reference
  output_kind: skill-reference-or-deferral
created: 2026-06-27
updated: 2026-06-28
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

## Implementation notes

- Added `.agents/skills/next-site/SKILL.md` as a concise site stack reference.
- Added source-grounded synthesis at `.research/analysis/briefs/next-site-skill-base.md`.
- Added attestations for local site guidance/config/source and current Next/React/Tailwind docs.
- Linked the reference from root `AGENTS.md` and `site/CLAUDE.md`.
- Checked current package/API versions: local Next/React are close to current npm latest; Tailwind/PostCSS are version-range pinned; ESLint/TypeScript latest majors are newer than local ranges and should not be copied blindly.
- Recorded README deploy drift in the synthesis/skill: current agent-facing deploy guidance should prefer `site/CLAUDE.md`, `site/Dockerfile`, and `next.config.ts` until README cleanup is scoped.

## Acceptance

- [x] Either a concise site stack reference exists and is linked, or the item records a clear deferral rationale.
- [x] If authored, it uses current Next/React/Tailwind docs rather than stale assumptions.
