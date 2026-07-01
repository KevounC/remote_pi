---
id: epic-bold-split-pi-extension-index
kind: epic
stage: done
tags: [refactor, bold, pi-extension]
parent: null
depends_on: [epic-bold-generated-protocol, epic-bold-canonical-session, epic-bold-turn-state-machine]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# pi-extension/src/index.ts is four modules pretending to be one file

## Thesis
The 4288-line god file and its ~30 module-level globals are four real modules
that were never named. Name them; make `index.ts` a thin composition root.
Globals become each module's private state.

## Lens
Inversion

## Impact
`pi-extension/src/index.ts` is the architectural gravity well: simultaneously
extension factory, relay transport lifecycle, remote-owner multiplexer
(`_activePeers` fanout), Pi SDK session projection (`_messageBuffer`,
`_sessionStartedAt`, turn wiring), and CLI/command/daemon/pairing surface —
holding ~30 module-level mutable globals (`index.ts:128-588`, `1300-1315`). The
composition root is buried *inside* the god file instead of wiring named modules
together. This is the enabling refactor: you can't make `RemoteSession` or the
turn state machine canonical while they're smeared across 30 globals in one file.
After this epic, `index.ts` wires four named modules with explicit interfaces;
the globals become each module's private state.

## Cost
Large mechanical refactor with behavior-preservation risk — must keep the Pi SDK
event wiring correct through the split. The black-box test applies: if it changes
observable behavior it's not a pure refactor and routes as feature work. Hardest
part: the four concerns are genuinely coupled through shared globals, so teasing
them apart requires introducing explicit interfaces between them. Sequenced last
(after protocol, canonical-session, turn-state-machine) so the modules it extracts
*into* already have their reconceived shapes to land in.

## Child features (riskiest first)
- **epic-bold-split-pi-extension-index-composition-root** *(riskiest — design
  this first; the module interface boundaries are what the split hangs on, and
  they must be defined before any module can be extracted)* — the thin `index.ts`
  composition root + the four module interfaces.
- epic-bold-split-pi-extension-index-relay-transport-module — relay transport
  lifecycle (reconnect, liveness, control frames) as a named module; adopts the
  reachability contract.
- epic-bold-split-pi-extension-index-owner-multiplexer-module — `_activePeers`
  fanout + pairing as a named module.
- epic-bold-split-pi-extension-index-sdk-session-projection-module —
  `_messageBuffer` / `_sessionStartedAt` / turn wiring as a named module;
  projects from canonical-session + turn-state-machine.
- epic-bold-split-pi-extension-index-cli-daemon-pairing-module — CLI/command /
  daemon / cron / pairing as a named module.

## Decomposition

Decomposition pre-existed (bold-refactor scan) — child features listed above in "Child features (riskiest first". Advanced to implementing via epic-design Phase 1.5 short-circuit.
