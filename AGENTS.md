# AGENTS.md — Remote Pi private fork

This checkout is the operator's private fork of Remote Pi.

## Repository posture

- Fork remote: `origin` → `https://github.com/KevounC/remote_pi.git`.
- Upstream remote: `upstream` → `https://github.com/jacobaraujo7/remote_pi.git` with push disabled.
- Push private-carry work only to `origin` unless the operator explicitly asks for an upstream PR.
- Treat upstream as read-only comparison/reference.

## Work tracking

This fork has its own `.work/` queue. Use it for Remote Pi code/product bugs, follow-up slices, and fork-owned operational work.

- `.work/backlog/` — parked bugs and ideas.
- `.work/active/stories/` — scoped implementation-sized work.
- `.work/active/features/` — multi-story or design-bearing work.
- `.work/active/epics/` — larger arcs.
- `.work/CONVENTIONS.md` — frontmatter, tags, and routing rules.

Do **not** park Remote Pi code/product bugs in the SNC root `.work/` queue. SNC root can record high-level operator context, but concrete Remote Pi implementation work belongs here.

## Existing project guidance

Read `CLAUDE.md` at the repo root for the orchestration/planning posture, and read the subproject `CLAUDE.md` before editing that subproject:

- `pi-extension/CLAUDE.md` — Node/TypeScript Pi extension.
- `app/CLAUDE.md` — Flutter mobile app.
- `relay/CLAUDE.md` — Rust relay.
- `cockpit/CLAUDE.md` — Flutter desktop cockpit.
- `site/CLAUDE.md` — site.

Root is primarily planning/orchestration. Code edits normally belong in the relevant subproject.

## Common commands

From `pi-extension/`:

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

Do not commit generated `dist/`, build artifacts, local `.pi/`, or secrets.
