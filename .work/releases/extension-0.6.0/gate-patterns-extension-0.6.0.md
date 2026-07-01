---
id: gate-patterns-extension-0.6.0
kind: story
stage: done
tags: [patterns, pi-extension]
parent: null
depends_on: []
release_binding: extension-0.6.0
gate_origin: patterns
created: 2026-07-01
updated: 2026-07-01
---

# Patterns extracted for extension-0.6.0

## New patterns codified
- `command-surface-adapter-classes` — Keep command-surface logic in thin, dependency-injected adapter classes.
- `typed-wire-decoders` — Parse/validate untrusted wire payloads through typed decode helpers before dispatch.
- `subscription-unsubscribe-contract` — Return explicit unsubscribe closures for every dynamic event subscription.

## Inconsistencies flagged
- None.

## Pattern files written
- `.agents/skills/patterns/SKILL.md`
- `.agents/skills/patterns/command-surface-adapter-classes.md`
- `.agents/skills/patterns/typed-wire-decoders.md`
- `.agents/skills/patterns/subscription-unsubscribe-contract.md`
- `.agents/rules/patterns.md`
- `.claude/skills/patterns` (compatibility link)
