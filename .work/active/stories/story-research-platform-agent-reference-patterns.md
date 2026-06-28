---
id: story-research-platform-agent-reference-patterns
kind: story
stage: done
tags: [research, docs, workflow]
parent: feature-agent-reference-surface
depends_on: []
research_dials:
  scope_authority: mixed
  verification_rigor: floor
  intent: platform-reference-pattern-transfer
  output_kind: reference-pattern-note
created: 2026-06-27
updated: 2026-06-27
---

# Research platform-style agent reference patterns

Study SNC `platform/` as the mature local example for how to impart language, library, and development-cycle knowledge to coding agents.

## Scope

- Read `/home/agent/SNC/platform/AGENTS.md`.
- Sample several `/home/agent/SNC/platform/.claude/skills/*/SKILL.md` tech references.
- Note how platform separates quick API references, project conventions, testing commands, scan rules, and research-backed positions.
- Translate the pattern to Remote Pi's simpler repo without overbuilding.

## Output

- Recommendation for Remote Pi reference location and naming (`.agents/skills`, `.claude/skills`, subproject-local references, or hybrid).
- Minimal template for a Remote Pi stack reference skill.
- List of first-wave references and any deferrals.

## Implementation notes

- Added `docs/agent-reference-surface.md` with the recommendation, template, first-wave references, integration plan, and deferrals.
- Updated `AGENTS.md` to name the new reference-surface convention and point agents at the pattern doc.
- Recommendation: canonical reference docs should live in `.agents/skills/<reference>/SKILL.md`, with `CLAUDE.md` files linking to them rather than owning API facts.
- Confirmed first-wave reference items remain appropriate: Pi extension TypeScript, Flutter mobile, Rust relay, mobile remote-coding best practices, Flutter desktop cockpit, and optionally/deferred Next site. The mobile remote-coding skill is tracked as a sibling feature rather than a child of `feature-agent-reference-surface`.
- Review pass `25673b12-b296-4ce` approved the story with no blockers. Follow-up nits addressed here: added `research_dials`, clarified package-shipped `pi-extension/skills/` vs repo-editing `.agents/skills/`, and clarified first-wave reference wording. The already-drafted `.agents/skills/pi-extension-typescript/SKILL.md` belongs to sibling `story-api-reference-pi-extension-typescript-stack` and remains in progress.

## Acceptance

- [x] Recommendation explicitly accounts for non-Claude agents and the existing Claude/cmux pane workflow.
- [x] Template covers imports, API quick reference, gotchas, anti-patterns, commands, tests, and project-specific lifecycle notes.
- [x] Follow-up reference-authoring items are confirmed or adjusted.
