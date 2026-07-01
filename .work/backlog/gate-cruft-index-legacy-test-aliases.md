---
id: gate-cruft-index-legacy-test-aliases
kind: story
stage: drafting
tags: [cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-01
---

# Migrate legacy index test aliases to the named harness

## Confidence
Medium

## Category
compatibility shim

## Location
`pi-extension/src/index.ts:2223`

## Evidence
```ts
// Legacy compatibility aliases. Keep these private test exports available while
// new tests migrate to the named harness above.
export const _connectForTest = remotePiTestHarness.connect;
export const _stopForTest = remotePiTestHarness.stop;
export const _getState = remotePiTestHarness.state;
export const routeClientMessage = remotePiTestHarness.routeClientMessage;
```

## Removal
Update extension tests and compatibility probes to import/use `remotePiTestHarness` directly, then remove these legacy aliases from `index.ts`. Keep only the named harness as the test seam.
