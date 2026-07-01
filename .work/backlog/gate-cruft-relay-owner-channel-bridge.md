---
id: gate-cruft-relay-owner-channel-bridge
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

# Retire temporary relay owner-channel bridge

## Confidence
Medium

## Category
compatibility shim

## Location
`pi-extension/src/extension/relay_transport.ts:57`

## Evidence
```ts
  /**
   * @internal Temporary owner-channel bridge while legacy call sites still need
   * direct access to the live RelayClient. Remove when owner ingress is fully
   * routed through RelayTransportPort.
   */
  currentRelayForOwnerChannels(): RelayClient | null;
```

## Removal
Finish routing owner ingress through `RelayTransportPort`/owner multiplexer APIs so `index.ts` no longer needs direct `RelayClient` access, then remove `currentRelayForOwnerChannels()` and its index call sites.
