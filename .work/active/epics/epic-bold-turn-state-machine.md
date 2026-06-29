---
id: epic-bold-turn-state-machine
kind: epic
stage: implementing
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: null
depends_on: [epic-bold-generated-protocol]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# The turn is a named state machine, not four booleans

## Thesis
One explicit algebraic `Turn` lifecycle replaces the fistful of booleans
(`_currentTurnId` / `_turnActive` / `_finishedTurnIdAwaitingSync` /
`_queuedMessage` / `_working` / `_workingReplyTo` / `AgentStatus` /
`_pendingSend`) smeared across four subsystems. Every consumer projects from the
same transition events.

## Lens
Algebraic

## Impact
The pi-extension's turn lifecycle is an unnamed global state machine
(`index.ts:538-544`); `_working` is maintained by **three loosely-coupled
signals** (pi room_meta, relay merge-patch, app local correction) that must
converge — the direct cause of `story-mobile-working-status-stuck` and the
"spinning sending" false-timeout symptom. `_finishedTurnIdAwaitingSync`
(`index.ts:540`) is a *named state* pretending to be a nullable string. A single
`Turn` type — `Idle → Working(replyTo) → Streaming → Done(awaitingSync) → Idle`
with lawful transitions — makes every consumer (pi-extension broadcast, app
working pill, relay `room_meta.working`, cockpit `AgentStatus`) a projection. The
"three signals converging" bug class becomes structurally impossible.

## Cost
Defining the transitions precisely is the hard part — the turn has real
subtleties: steer (mid-turn redirect), cancel, compaction (manually brackets
working today, `index.ts:1524-1537`), and session replacement mid-turn. Gets
dramatically easier after the generated-protocol epic (turn events are wire
messages). The riskiest child is proving the state set can hold all four edge
cases without becoming a state explosion.

## Child features (riskiest first)
- **epic-bold-turn-state-machine-algebraic-state** *(riskiest — design this
  first; the whole epic hangs on whether a small state set can hold steer /
  cancel / compaction / mid-turn session replacement without explosion)* — the
  canonical `Turn` states + transition rules; the edge-case feasibility proof.
- epic-bold-turn-state-machine-projection-consumers — pi-extension broadcast,
  app working pill, relay `room_meta.working`, cockpit `AgentStatus` all become
  projections of the transition events.
- epic-bold-turn-state-machine-late-attach — `_finishedTurnIdAwaitingSync`
  becomes the `Done(awaitingSync)` state; late-attaching owners hydrate from it
  instead of a special-case nullable.

## Decomposition

Decomposition pre-existed (bold-refactor scan) — child features listed above in "Child features (riskiest first". Advanced to implementing via epic-design Phase 1.5 short-circuit.
