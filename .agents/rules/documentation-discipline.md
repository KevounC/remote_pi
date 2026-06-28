# Documentation Discipline

Persistent docs are current-state operating surfaces, not progress logs. Keep agent-facing rules and references concise, durable, and directly useful.

## Current state, not history

When a position changes, rewrite the owning artifact in place. Do not append a new historical layer unless the old path is hazardous enough to name as a rejected alternative.

Good durable artifacts state:

- the current rule or convention;
- the load-bearing reason when non-obvious;
- serious rejected alternatives when a future agent might otherwise re-open them;
- revisit conditions when the rule depends on assumptions that can change.

## Artifacts defend themselves inline

Do not create a separate decision tier for normal repo decisions. A decision worth preserving belongs in the artifact it governs:

- protocol constraints in `PROTOCOL.md`;
- agent behavior in `.agents/rules/`;
- stack/API facts in `.agents/skills/<reference>/SKILL.md`;
- subproject workflow in the subproject `CLAUDE.md`;
- work queue conventions in `.work/CONVENTIONS.md`.

If you encounter important rationale stranded in a plan, chat note, or work item while editing, move or summarize it into the durable artifact that owns it.

## Link discipline

Use two path forms:

- Markdown links for clickable references, with file-relative paths: `[PROTOCOL.md](../../PROTOCOL.md)`.
- Backtick project-rooted prose mentions for non-clickable hints: `PROTOCOL.md`, `.agents/rules/code-design.md`, `pi-extension/src/index.ts`.

Avoid absolute paths in committed docs. Absolute paths are acceptable only in private session notes or local chat when pointing at another checkout for comparison.

## Durable references do not point down into work items

`.work/` is transient. Durable docs may mention work item slugs in prose, but they must not rely on links into `.work/` for their operative meaning. If a work item produced a durable rule/reference/doc, link the durable output instead.

## README audience

READMEs are for human orientation. Do not use a README as an agent rulebook or progress log.

- User install/setup/troubleshooting belongs in README.
- Agent routing, workflow, and implementation rules belong in `AGENTS.md`, subproject `CLAUDE.md`, `.agents/rules/`, or `.agents/skills/`.
- Avoid duplicating detailed frontmatter schemas or agent workflow steps in README unless a human operator genuinely needs them.

## Reference surface hygiene

`.agents/skills/<reference>/SKILL.md` files are agent-readable stack/reference docs. Keep them:

- version-aware;
- grounded in local package files and current upstream docs when APIs are version-sensitive;
- scoped to the paths they govern;
- concrete about commands, gotchas, anti-patterns, and review checks;
- free of stale TODO lists and implementation progress chatter.

When Claude-facing `CLAUDE.md` files need API facts, prefer a pointer to the `.agents/skills/` reference instead of duplicating the facts.
