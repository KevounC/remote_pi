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

## Agent reference surface

Remote Pi is adopting platform-style agent references so implementation/review agents have current language, library, and development-cycle guidance before touching code. The pattern and template live at `docs/agent-reference-surface.md`. New canonical references should prefer `.agents/skills/<reference>/SKILL.md` so Pi/Codex/non-Claude agents can read them directly; Claude-facing files may link to those references but should not become the only source of API facts.

First-wave references are tracked in `.work/active/features/feature-agent-reference-surface.md` and children. Available references:

- `.agents/skills/pi-extension-typescript/SKILL.md` — `pi-extension/` TypeScript/Pi SDK lifecycle work.
- `.agents/skills/flutter-mobile/SKILL.md` — `app/` Flutter mobile lifecycle, provider/ViewModels, routing, WebSocket reconnect, and room/session state.
- `.agents/skills/mobile-remote-coding/SKILL.md` — cross-cutting mobile remote-coding state-machine and reconnect checklist for app/extension/relay work.

Until the rest are authored, agents should treat subproject `CLAUDE.md` files plus `PROTOCOL.md` as the minimum required context.

## Common commands

From `pi-extension/`:

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

Do not commit generated `dist/`, build artifacts, local `.pi/`, or secrets.
