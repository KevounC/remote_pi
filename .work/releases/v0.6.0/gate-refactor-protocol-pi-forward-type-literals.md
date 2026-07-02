---
id: gate-refactor-protocol-pi-forward-type-literals
kind: story
stage: done
tags: []
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Pi forward client handwrites generated cross-PC discriminators

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`pi-extension/src/transport/pi_forward_client.ts:63,95`

## Issue
`PiForwardClient` still writes and checks `"pi_envelope"` / `"pi_envelope_in"` literals even though `crossPcTypes` and the generated `CrossPcFrame*` DTOs define the cross-PC frame discriminators.

## Fix
Build and narrow cross-PC frames through a generated helper/constant or generated decoder so the discriminator values derive from `crossPcTypes` instead of being retyped by hand.
