---
id: story-research-platform-agent-reference-patterns
kind: story
stage: drafting
tags: [research, docs, workflow]
parent: feature-agent-reference-surface
depends_on: []
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

## Acceptance

- Recommendation explicitly accounts for non-Claude agents and the existing Claude/cmux pane workflow.
- Template covers imports, API quick reference, gotchas, anti-patterns, commands, tests, and project-specific lifecycle notes.
- Follow-up reference-authoring items are confirmed or adjusted.
