# Remote Pi work conventions

This `.work/` tier tracks private-fork work that is specific to `KevounC/remote_pi`.
Use it for bugs, follow-up slices, and product/ops ideas that belong with the fork's code rather than in the SNC root queue.

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
created: YYYY-MM-DD
updated: YYYY-MM-DD
---
```

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
