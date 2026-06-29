---
id: epic-bold-split-pi-extension-index-sdk-session-projection-module
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Split pi-extension index — SDK session projection module

## Brief
`_messageBuffer` / `_sessionStartedAt` / turn wiring extracted from `index.ts`
as a named module that projects from the canonical-session and
turn-state-machine epics. Globals `_sessionStartedAt`, `_messageBuffer`,
`_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`,
`_queuedMessage` (`index.ts:408-424`, `:538-544`) become this module's private
state — or, where the turn-state-machine epic has already named them, delegate
to it.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`; overlaps with
  `epic-bold-turn-state-machine` (the turn globals move there, this module
  holds the rest).

## Foundation references
- Evidence: `pi-extension/src/index.ts:408-424`, `:538-544`, `:1355-1625`,
  `:1446-1470`, `:3538-3590`.

<!-- /agile-workflow:refactor-design pins the module boundary. -->
