---
id: gate-refactor-protocol-room-meta-literal
kind: story
stage: implementing
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Relay transport handwrites the room_meta_update discriminator

## Library
protocol-contract

## Rule
handwritten-type-string

## Confidence
High

## Location
`pi-extension/src/extension/relay_transport.ts:255`

## Issue
`sendRoomMeta` constructs `{ type: "room_meta_update" }` by hand even though `relayControlTypes` / `RelayControlFrameRoomMetaUpdate` define the discriminator in the generated protocol registry.

## Fix
Build the room metadata update through the generated relay control frame type (or a small helper typed as `RelayControlFrameRoomMetaUpdate`) so the discriminator and payload shape derive from the generated registry.
