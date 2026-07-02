---
id: gate-patterns-v0.6.0
kind: story
tags: [patterns]
stage: done
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: patterns
created: 2026-07-01
updated: 2026-07-01
---

# Patterns extracted for v0.6.0

## New patterns codified
- `snapshot-replay-event-mappers` — Convert protocol snapshots/legacy payloads into canonical event lists before projection.
- `reachability-contract-projection` — Project the shared reachability contract into each stack with clamped policy helpers.

## Inconsistencies flagged
- None.

## Pattern files written
- `.agents/skills/patterns/SKILL.md`
- `.agents/skills/patterns/snapshot-replay-event-mappers.md`
- `.agents/skills/patterns/reachability-contract-projection.md`
- `.agents/rules/patterns.md`
- `.claude/skills/patterns/SKILL.md`
- `.claude/skills/patterns/snapshot-replay-event-mappers.md`
- `.claude/skills/patterns/reachability-contract-projection.md`

## Notes

- `gate-patterns v0.6.0` output was manually validated against the release scope and persisted artifacts.
