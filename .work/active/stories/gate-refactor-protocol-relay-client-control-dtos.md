---
id: gate-refactor-protocol-relay-client-control-dtos
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: extension-0.6.0
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Relay client redeclares generated relay control frame DTOs

## Library
protocol-contract

## Rule
handwritten-wire-dto

## Confidence
High

## Location
`pi-extension/src/transport/relay_client.ts:25`

## Issue
`HelloMsg`, `ChallengeMsg`, `AuthMsg`, and `RoomMetaUpdateFrame` hand-declare relay wire frames even though `protocol.generated.ts` exports `RelayControlFrameHello`, `RelayControlFrameAuth`, `RelayControlFrameChallenge`, and `RelayControlFrameRoomMetaUpdate`.

## Fix
Import or derive the relay client frame types from `pi-extension/src/protocol/generated/protocol.generated.ts`; remove the handwritten mirrors and reconcile the local `room_meta`/`room_id` optionality with the generated DTOs.
