---
id: gate-refactor-boundaries-demux-adhoc-map
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

# WebSocket post-auth demux parses frames through an ad-hoc map

## Library
boundaries

## Rule
ad-hoc-wire-parse

## Confidence
Medium

## Location
app/lib/data/transport/ws_transport.dart:287

## Issue
demuxPostAuthInboundFrame decodes untrusted WS frames as Map<String, dynamic> and manually navigates peer, ct, room, type. No Dart generated DTO covers this top-level relay frame — a typed-boundary gap.

## Fix
needs analysis: add a typed DTO for the top-level relay frame
