---
id: gate-refactor-protocol-outbound-frames-undocumented-island
kind: story
stage: drafting
tags: []
parent: null
depends_on: []
release_binding: null
gate_origin: refactor
created: 2026-07-01
updated: 2026-07-01
---

# Relay outbound control frames are an undocumented hand-maintained protocol island

## Library
protocol-contract

## Rule
undocumented-protocol-island

## Confidence
Medium

## Location
relay/src/peers/registry_event_publisher.rs:49

## Issue
Relay outbound frames such as room_announced, room_ended, peer_online, peer_offline, and room_meta_updated are hand-built with JSON/type strings outside generated protocol DTOs. The same island continues for snapshot frames in connection_actor.rs:216 and :236 (presence, rooms). No local reason documenting why these wire shapes are outside the generated schema.

## Fix
needs analysis: migrate these outbound relay frames to generated/schema-backed DTOs, or document the temporary island and migration condition.
