---
id: gate-refactor-protocol-pi-forward-crosspc-dtos
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: extension-0.6.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Pi forward client redeclares generated cross-PC frame DTOs

## Library
protocol-contract

## Rule
handwritten-wire-dto

## Confidence
High

## Location
`pi-extension/src/transport/pi_forward_client.ts:22`

## Issue
`PiEnvelopeFrame` / `PiEnvelopeInFrame` hand-maintain the cross-PC wire shape while `protocol.generated.ts` exports `CrossPcFramePiEnvelope`, `CrossPcFramePiEnvelopeIn`, and `CrossPcFrame` for the same discriminators.

## Fix
Replace the local frame interfaces with generated cross-PC frame types and keep only adapter/domain conversion around the existing `Envelope` type where needed.
