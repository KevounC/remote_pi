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

## Absorbed from `story-investigate-model-thinking-actions-after-session-replacement` (retired 2026-06-29)

The retired investigation pinned a concrete consequence of the module-level
`_pi` global: after app-triggered `session_new`, valid app `model_set` and
`thinking_set` actions may return `action_error` until a full reload/restart,
because they route through stale `_pi.setModel()` / `_pi.setThinkingLevel()`
while the prompt path has a fresh `_messageApi`. The SDK-session-projection
module must expose fresh model/thinking setters on the replacement context (or
a fresh action-API wrapper) — not route through a stale module global. If the
SDK cannot expose fresh setters on `ReplacedSessionContext` / `session_start`,
this module records the SDK gap and degrades explicitly.

## Absorbed from `story-fix-cross-pc-bridge-late-attach-after-shutdown` (retired 2026-06-29)

The retired story pinned an async-teardown race in `MeshNode.attachBridge()` /
`attachCrossPcBridge()`: a `PiForwardClient` can be constructed, await sibling
discovery, and install `BrokerRemote` listeners *after* `MeshNode.close()` or
session shutdown if teardown lands during the async discovery window —
creating stale cross-PC routing state / ghost listeners. The SDK-session-
projection module (and the relay-transport module's teardown) must enforce a
post-await closed/epoch check on every bridge-attach continuation; `BrokerRemote
.handleIncoming`, `PlainPeerChannel`, and `PiForwardClient` must carry internal
detached guards, not rely solely on listener removal/upstream detach.

<!-- /agile-workflow:refactor-design pins the module boundary. -->
