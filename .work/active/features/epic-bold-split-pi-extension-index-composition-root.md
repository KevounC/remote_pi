---
id: epic-bold-split-pi-extension-index-composition-root
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Split pi-extension index — composition root (riskiest — design first)

## Brief
The thin `index.ts` composition root + the four module interfaces (relay
transport, owner multiplexer, SDK session projection, CLI/daemon/pairing). The
module interface boundaries are what the split hangs on — they must be defined
before any module can be extracted, since the four concerns are genuinely
coupled through shared globals today.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: riskiest child — the interface boundaries are what the rest hangs
  on. Design FIRST.

## Foundation references
- Evidence: `pi-extension/src/index.ts:35-180` (imports + global state),
  `:1327-1619` (Pi SDK event wiring), `:1635-1688` (command dispatch),
  `:3217-3588` (client-message router).

<!-- /agile-workflow:refactor-design pins the module interfaces. -->
