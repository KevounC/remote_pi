---
id: feature-agent-reference-surface
kind: feature
stage: drafting
tags: [workflow, research, docs]
parent: epic-remote-session-resilience-refactor
depends_on: []
created: 2026-06-27
updated: 2026-06-27
---

# Platform-style agent reference surface

Remote Pi's current agent guidance is mostly `CLAUDE.md` prose plus per-pane orchestration notes. Before larger agentic refactors, build a mature agent reference surface modeled on SNC `platform/`: concise stack references, API quick references, gotchas, anti-patterns, commands, and verification recipes that agents read before touching each subproject.

## Reference model

Use `/home/agent/SNC/platform/AGENTS.md` and `/home/agent/SNC/platform/.claude/skills/*/SKILL.md` as the pattern:

- one stack/library reference per significant language/library surface;
- imports/API quick reference;
- project-specific conventions and gotchas;
- test/build/dev-cycle commands;
- anti-patterns that have already caused or could plausibly cause defects;
- clear instruction in `AGENTS.md`/`CLAUDE.md` for non-Claude agents to read these files directly.

Prefer an agent-neutral location if practical (for example `.agents/skills/<topic>/SKILL.md`), with `.claude/` compatibility only if needed by the current Claude-pane workflow.

## Child research/reference items

- `story-research-platform-agent-reference-patterns`
- `story-api-reference-pi-extension-typescript-stack`
- `story-api-reference-flutter-mobile-stack`
- `story-api-reference-rust-relay-stack`
- `story-api-reference-flutter-desktop-cockpit-stack`
- `story-api-reference-next-site-stack`

## Draft acceptance

- The chosen reference-file location and naming convention are documented in this repo.
- Each actively edited stack has a current API/reference skill or explicit rationale for deferral.
- `AGENTS.md` tells future agents to load the relevant reference before implementation/review.
- The reference surface includes both language/library APIs and Remote Pi-specific lifecycle/protocol gotchas.
