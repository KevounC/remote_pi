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

## Agent operating discipline

Before designing, implementing, or reviewing, read the agent-neutral rules in `.agents/rules/`:

- `.agents/rules/agent-discipline.md` — startup checklist, cwd/subproject boundaries, fork posture, durable-vs-transient artifacts.
- `.agents/rules/code-design.md` — ports/adapters, single source of truth, generated/inferred contracts, fail-fast boundaries, lifecycle ownership.
- `.agents/rules/documentation-discipline.md` — current-state docs, inline self-defense, link/reference hygiene, README audience.
- `.agents/rules/testing-integrity.md` — no gaming tests, failure triage, subproject verification commands.

These files are harness-neutral. If Pi's agile-workflow extension auto-loads `.agents/rules/`, still read the relevant rule body directly when a task depends on it.

## Existing project guidance

Read `CLAUDE.md` at the repo root for the orchestration/planning posture, and read the subproject `CLAUDE.md` before editing that subproject:

- `pi-extension/CLAUDE.md` — Node/TypeScript Pi extension.
- `app/CLAUDE.md` — Flutter mobile app.
- `relay/CLAUDE.md` — Rust relay.
- `cockpit/CLAUDE.md` — Flutter desktop cockpit.
- `site/CLAUDE.md` — site.

`CLAUDE.md` files are not Claude-exclusive when they describe project behavior; treat them as local reference docs. Root is primarily planning/orchestration. Code edits normally belong in the relevant subproject.

## Agent reference surface

Remote Pi is adopting platform-style agent references so implementation/review agents have current language, library, and development-cycle guidance before touching code. The pattern and template live at `docs/agent-reference-surface.md`. New canonical references should prefer `.agents/skills/<reference>/SKILL.md` so Pi/Codex/non-Claude agents can read them directly; Claude-facing files may link to those references but should not become the only source of API facts.

When picking up any active `.work` item tagged `research` or containing `research_dials`, load and follow the `research-orchestrator` skill before authoring research-backed docs, skills, briefs, or references. Treat the item's `research_dials` as the commissioning registration and surface/confirm them through that workflow rather than proceeding ad hoc.

First-wave references are tracked in `.work/active/features/feature-agent-reference-surface.md` and children. Available references:

- `.agents/skills/code-design-principles/SKILL.md` — generic design/implementation principles adapted from SNC/platform: ports/adapters, single source of truth, generated contracts, fail fast, lifecycle ownership, convergent state.
- `.agents/skills/pi-extension-typescript/SKILL.md` — `pi-extension/` TypeScript/Pi SDK lifecycle work.
- `.agents/skills/flutter-mobile/SKILL.md` — `app/` Flutter mobile lifecycle, provider/ViewModels, routing, WebSocket reconnect, and room/session state.
- `.agents/skills/rust-relay/SKILL.md` — `relay/` Rust async WebSocket routing, mesh membership, presence/rooms, logging/privacy, and relay tests.
- `.agents/skills/flutter-desktop-cockpit/SKILL.md` — `cockpit/` Flutter desktop lifecycle, shadcn/modular/Hive patterns, terminal/PTY, file/window/native plugin surfaces, and cockpit tests.
- `.agents/skills/next-site/SKILL.md` — `site/` Next App Router, React Server/Client Components, Tailwind 4/PostCSS, standalone Docker deploy, and site lint/build workflow.
- `.agents/skills/mobile-remote-coding/SKILL.md` — cross-cutting mobile remote-coding state-machine and reconnect checklist for app/extension/relay work.

Until the rest are authored, agents should treat subproject `CLAUDE.md` files plus `PROTOCOL.md` as the minimum required context. Prefer adding future reusable references under `.agents/skills/`; use `.claude/skills/` only as a compatibility mirror or pointer, not as the canonical source of generic API/design facts.

## Common commands

Run commands from the owning subproject root.

From `pi-extension/`:

```bash
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
```

From `app/`:

```bash
flutter analyze
flutter test
```

From `relay/`:

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo test
```

From `cockpit/`:

```bash
flutter analyze
flutter test
```

From `site/`:

```bash
pnpm lint
pnpm build
```

Do not commit generated `dist/`, build artifacts, local `.pi/`, or secrets.
