---
id: gate-docs-peer-join-broadcast-location
kind: story
stage: drafting
tags: [documentation]
parent: null
depends_on: []
release_binding: null
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# `peer_joined/peer_left` broadcast comment points to wrong module

## Drift category
foundation-doc-assertion

## Location
- `pi-extension/src/session/broker_remote.ts:416-421`
- `pi-extension/src/session/broker.ts:323-324`, `pi-extension/src/session/broker.ts:411`

## Current doc text
"...`lastLocalPeers` because that cache is fed by the `peer_joined`/`peer_left` broadcast in `index.ts` ..."

## Reality
The local peer presence broadcasts are emitted by `pi-extension/src/session/broker.ts` (`_broadcastSystem({ type: "peer_joined" ... })` and `peer_left`). `broker_remote.ts` currently receives these control envelopes but should not describe `index.ts` as their source.

## Required edit
Replace module references in this comment block to reflect the real source (`session/broker.ts`) and avoid implying `index.ts` emits `peer_joined`/`peer_left` broadcasts.