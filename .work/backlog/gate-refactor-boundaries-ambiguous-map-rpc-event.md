---
id: gate-refactor-boundaries-ambiguous-map-rpc-event
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

# RPC domain events carry untyped wire blobs

## Library
boundaries

## Rule
ambiguous-map-to-domain

## Confidence
Medium

## Location
cockpit/lib/app/cockpit/domain/entities/rpc_event.dart:68,269

## Issue
RpcToolStart.args and RpcMeshRevoked.details move Map<String, dynamic> payloads into domain events instead of narrowing them at the adapter boundary.

## Fix
Needs analysis: introduce typed DTOs or an explicit opaque JsonObject value object and have RpcEventMapper produce that boundary type.
