# Agent reference surface pattern

Remote Pi is moving from ad-hoc `CLAUDE.md` guidance toward a platform-style reference surface for agentic coding. The model is SNC `platform/`: project instructions tell agents which reference to load, and each stack/library reference carries quick API facts, commands, gotchas, and anti-patterns close to the codebase.

## Source pattern studied

- `/home/agent/SNC/platform/AGENTS.md` — indexes build/test commands, tech references, research/work bands, coding conventions, and agent commands.
- `/home/agent/SNC/platform/.claude/skills/hono-v4/SKILL.md` — versioned framework reference with imports, API snippets, validation/openapi patterns, gotchas, and anti-patterns.
- `/home/agent/SNC/platform/.claude/skills/drizzle-v0/SKILL.md`, `zod-v4/SKILL.md`, and scan-rule skills — same convention applied to library APIs and review lenses.
- `/home/agent/forks/remote_pi/AGENTS.md` and subproject `CLAUDE.md` files — current Remote Pi guidance is useful but mostly persona/orchestration prose, not API-reference substrate.

## Recommendation

Use an **agent-neutral primary location** at the repo root:

```text
.agents/skills/<reference-name>/SKILL.md
```

Then point both `AGENTS.md` and subproject `CLAUDE.md` files at those references. This keeps the source usable by Pi/Codex/non-Claude agents while still readable by Claude panes. It also gives root-level orchestrators one index for cross-cutting references such as `PROTOCOL.md` and mobile/relay session semantics.

Rejected/qualified alternative: subproject-local `.claude/skills/<topic>/SKILL.md` mirrors the current platform implementation and fits the existing cmux panes, but it would make Claude-specific paths the canonical API surface and scatter cross-cutting protocol facts across subprojects. Use subproject-local files only as thin pointers or for genuinely subproject-private references if later proven necessary. Existing package-shipped skills such as `pi-extension/skills/agent-network/SKILL.md` are a different class: runtime/user-facing extension resources distributed with the package, not the canonical repo-editing reference surface.

Recommended first wave:

| Reference | Scope | Priority |
|---|---|---|
| `pi-extension-typescript` | `pi-extension/`: Pi SDK lifecycle, Node ESM/TypeScript, `ws`, schema/crypto/keyring, mesh gotchas | High |
| `flutter-mobile` | `app/`: Flutter/Dart lifecycle, provider/ViewModels, `go_router`, WebSocket reconnect, secure storage/Hive | High |
| `rust-relay` | `relay/`: Tokio/Axum WebSocket relay, serde, tracing, error handling, security constraints | High |
| `mobile-remote-coding` | Cross-cutting mobile/relay/mesh UX and state-machine best practices | High |
| `flutter-desktop-cockpit` | `cockpit/`: Flutter desktop, shadcn, modular, PTY/window/file surfaces | Medium |
| `next-site` | `site/`: Next/React/Tailwind site surface | Defer unless site work becomes active |

## Minimal stack-reference template

Each stack reference should use this shape:

~~~md
---
name: <reference-name>
description: <when an agent should load this reference>
updated: YYYY-MM-DD
---

# <Stack / Library> Reference

> Version/context: <versions from package files or lockfiles>
> Canonical docs: <official docs URLs>
> Local scope: <repo paths governed by this reference>

## When to load

- <Path or task triggers>

## Imports / entry points

```<language>
// Common imports or entry files used in this repo
```

## API quick reference

Short examples of the APIs agents actually touch in this repo. Prefer verified current docs over memory when APIs are version-sensitive.

## Project conventions

- Naming, layering, dependency direction.
- Error-handling style.
- Logging/observability style.
- Config/secrets handling.

## Remote Pi lifecycle/protocol gotchas

- Session replacement (`/new`, `/resume`, reload) behavior.
- Reconnect hydration and stale event handling.
- Working/idle/error state convergence.
- Multi-client vs mesh-peer semantics.

## Anti-patterns

- Concrete things not to do, grounded in repo bugs or likely failure modes.

## Commands and verification

- Install/build/typecheck/test commands from the relevant subproject root.
- Manual smoke checks for protocol or UI behavior.

## Review checklist

- Small, stack-specific checklist reviewers can apply before approving changes.
~~~

## Integration plan

1. Create `.agents/skills/<reference>/SKILL.md` for each high-priority reference.
2. Update root `AGENTS.md` with a `Tech References` section modeled on platform, telling non-Claude agents to read the markdown body directly.
3. Add one sentence to each subproject `CLAUDE.md` pointing to the relevant `.agents/skills` reference.
4. Keep `CLAUDE.md` as orchestration/persona guidance; keep API facts in `.agents/skills` so they do not drift across panes.
5. Use current upstream docs for version-sensitive APIs during authoring; record doc URLs in the reference frontmatter/body.

## Deferrals

- Full ARD-style `.research/` adoption is not required before writing these references. If later research becomes source-heavy or externally cited, add a dedicated `.research/` band. For this first pass, work items plus reference docs are sufficient.
- `site/` reference can be deferred until site code changes are planned.
