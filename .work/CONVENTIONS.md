# Remote Pi work conventions

This `.work/` tier tracks private-fork work that is specific to `KevounC/remote_pi`.
Use it for bugs, follow-up slices, and product/ops ideas that belong with the fork's code rather than in the SNC root queue.

Before advancing work items, read `AGENTS.md` and `.agents/rules/*.md`. The rule surface is agent-neutral; `.work/` is the queue, not the place to preserve lasting design/routing policy.

## Layout

- `backlog/` — parked bugs and ideas, flat files.
- `active/stories/` — scoped implementation-sized work.
- `active/features/` — multi-story or design-bearing work.
- `active/epics/` — larger arcs that decompose into features/stories.
- `archive/` — completed/retired items when they no longer need active bodies.

## Frontmatter

Backlog items use:

```yaml
---
id: <slug>
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [<tag>, ...]
---
```

Active items use:

```yaml
---
id: <kind>-<slug>
kind: epic|feature|story
stage: drafting|implementing|review|done
tags: [<tag>, ...]
parent: <id>|null
depends_on: [<id>, ...]
release_binding: <version>|null
gate_origin: <gate-name>|null
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

For normal user-scoped items, set `release_binding: null` until `release-deploy` binds the item to a release, and set `gate_origin: null` unless the item was produced by a release gate.

Research-tagged active items additionally carry an ARD-style registration block:

```yaml
research_dials:
  scope_authority: pre-registered|mixed|in-engagement-judgment
  verification_rigor: floor|standard|full
  intent: <short free-text inventory value>
  output_kind: <short free-text inventory value>
```

The operator-confirmed dials are part of scoping. If a research item lacks them, pause before dispatching research and confirm/register dials instead of silently proceeding.

When picking up any active item tagged `research` or containing `research_dials`, load and follow the `research-orchestrator` skill before authoring research outputs. Do not produce research-backed docs, skills, briefs, or references ad hoc; the item's `research_dials` are the commissioning registration and must be surfaced/confirmed according to the orchestrator workflow.

## Tags

Start small. Current tags:

- `pi-extension` — Node/TypeScript Pi extension work.
- `app` — Flutter mobile app work.
- `relay` — Rust relay work.
- `cockpit` — desktop cockpit work.
- `workflow` — developer/operator workflow for the fork.
- `research` — source-grounded discovery work whose output informs later implementation.
- `docs` — agent/reference documentation, skills, or operator docs.
- `bug` — observed defect or regression.

## Routing

- Keep code-owned Remote Pi bugs here.
- Keep SNC root `.work/` for SNC operational orchestration only.
- Keep `plan/` for broader architectural plans already used by this repo; `.work/` is the queue for concrete bugs/slices.
- Upstream contribution remains opt-in. Private-carry work can live here without opening upstream PRs.
