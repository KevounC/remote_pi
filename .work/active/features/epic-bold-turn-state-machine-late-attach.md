---
id: epic-bold-turn-state-machine-late-attach
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension, app]
parent: epic-bold-turn-state-machine
depends_on: [epic-bold-turn-state-machine-algebraic-state]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Turn — late-attach as the Done(awaitingSync) state

## Brief
`_finishedTurnIdAwaitingSync` (`pi-extension/src/index.ts:540`) is a *named
state* pretending to be a nullable string today — a special-case latch bridging
late-attaching owners after `agent_end`. Make it the `Done(awaitingSync)` state
of the canonical `Turn`; late-attaching owners hydrate from that state instead
of a special-case nullable. Retires the late-attach sync workaround
(`index.ts:3324-3337`).

## Epic context
- Parent epic: `epic-bold-turn-state-machine`
- Position: consumer of `algebraic-state`. Resolves the late-attach story
  (`story-fix-late-attach-turn-stream-sync`, `story-fix-cross-pc-bridge-late-attach-after-shutdown`)
  structurally rather than as patches.

## Foundation references
- Evidence: `pi-extension/src/index.ts:540`, `:1476-1484`, `:3324-3337`.

## Absorbed from `story-fix-cross-pc-bridge-late-attach-after-shutdown` (retired 2026-06-29)

The retired story's late-attach race (bridge attaches relay/broker listeners
after teardown) is one instance of the broader late-attach pattern the
`Done(awaitingSync)` state absorbs: an async continuation completing after the
owning lifecycle has closed. The `Done(awaitingSync)` transition must cover
not only late-attaching *owners* but any late-completing continuation whose
owning context may have torn down — the state is "awaiting sync" precisely
because the continuation may still land.

<!-- /agile-workflow:refactor-design pins the Done(awaitingSync) transition. -->
