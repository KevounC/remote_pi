---
id: epic-bold-turn-state-machine-algebraic-state
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension]
parent: epic-bold-turn-state-machine
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Turn — algebraic state set (riskiest — design first)

## Brief
The canonical `Turn` states + transition rules. Candidate set: `Idle →
Working(replyTo) → Streaming → Done(awaitingSync) → Idle`. The risk: the turn
has real subtleties — steer (mid-turn redirect), cancel, compaction (manually
brackets working today), and session replacement mid-turn. This feature must
prove a small state set can hold all four edge cases without state explosion
before the projection consumers and late-attach children commit to it.

## Epic context
- Parent epic: `epic-bold-turn-state-machine`
- Position: riskiest child — the state set's feasibility is what the rest of
  the epic hangs on. Design FIRST.

## Foundation references
- Evidence of the unnamed machine: `pi-extension/src/index.ts:538-544`
  (`_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`,
  `_queuedMessage`); compaction brackets `index.ts:1524-1537`; turn seed
  `index.ts:3284-3313`; agent end + late-sync `index.ts:1476-1484`,
  `:3324-3337`.

<!-- /agile-workflow:refactor-design pins the state set + transitions,
resolving the edge-case explosion risk. -->
