# Agent Discipline

These rules bind every agent working in this private fork, regardless of harness. Claude-specific files remain useful guidance, but the canonical agent-neutral surface is `AGENTS.md`, `.agents/rules/`, `.agents/skills/`, `.work/`, and durable docs.

## Startup checklist

Before designing, implementing, or reviewing:

1. Read root `AGENTS.md`.
2. Read every file in `.agents/rules/`.
3. Read the relevant subproject `CLAUDE.md` before touching that subproject.
4. Read the relevant `.agents/skills/<reference>/SKILL.md` stack/reference file when one exists.
5. Read `PROTOCOL.md` before changing wire format, relay, pairing, mesh, room/session metadata, mobile state, or cross-PC routing.

If a task starts from another repo such as SNC root, switch mental context explicitly: Remote Pi code/product work belongs in this checkout's `.work/`, not in SNC's queue.

## Cwd and subproject boundaries

Root is primarily planning/orchestration. Code edits normally belong in one subproject:

- `pi-extension/` — Pi extension, daemon/supervisor, agent mesh, pairing, relay client.
- `app/` — Flutter mobile app.
- `relay/` — Rust relay.
- `cockpit/` — Flutter desktop cockpit.
- `site/` — marketing/docs site.

Run build/test commands from the owning subproject root unless a command is documented as root-level. Do not make broad cross-subproject edits without saying which boundary is being changed and why.

## Third-party fork posture

This is a private fork of a third-party project. Upstream is read-only unless the operator explicitly asks for an upstream PR.

- Prefer private-carry changes that are well-isolated and easy to rebase.
- Keep upstream behavior unchanged unless the task explicitly calls for a product/fork divergence.
- When changing a fork policy, record the current policy and the rejected alternative in the artifact that owns the policy.

## Durable vs transient artifacts

- `.agents/rules/`, `.agents/skills/`, `AGENTS.md`, subproject `CLAUDE.md`, `PROTOCOL.md`, and `docs/` are durable agent/reference surfaces.
- `.work/` items are transient work state.
- Durable artifacts must not depend on links into `.work/` for their operative meaning. Mention work items by slug in prose if necessary; put lasting decisions in the durable artifact they govern.

## Generated and local state

Never commit generated output or machine-local runtime state:

- `dist/`, `build/`, `target/`, `.next/`, `.dart_tool/`, `node_modules/`, coverage output.
- local `.pi/` config, pairing state, key material, `.env*`, logs, or secrets.

If a command needs secrets or local state, run the documented command and let the subprocess read its environment. Do not copy secrets into chat or durable docs.
