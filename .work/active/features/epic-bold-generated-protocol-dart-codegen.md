---
id: epic-bold-generated-protocol-dart-codegen
kind: feature
stage: drafting
tags: [refactor, bold, app, pi-extension]
parent: epic-bold-generated-protocol
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Generated protocol — Dart codegen target (riskiest — design first)

## Brief
The feasibility hinge for the whole generated-protocol epic. Produce clean
Dart sealed `ClientMessage`/`ServerMessage` unions with `fromJson` narrowing
and codec parity with the TS targets, generated from the canonical schema —
absorbing today's 1313-line hand mirror in `app/lib/protocol/protocol.dart`.

The risk: Dart sealed-class codegen is the weak link across the three
languages. If clean generated sealed classes (with exhaustive `switch` and
`fromJson`) aren't feasible, the foundation's shape changes — likely a
schema-driven *hand-maintained* single source with a generated contract test,
which is a weaker (timid) posture the greenfield stance rejects. This feature
must prove the bold posture is actually achievable in Dart before the rest of
the epic commits to it.

## Epic context
- Parent epic: `epic-bold-generated-protocol`
- Position: riskiest child — the whole epic's shape depends on this landing
  cleanly. Design FIRST.

## Foundation references
- Evidence: `app/lib/protocol/protocol.dart:410-1180` (hand mirror to replace),
  `pi-extension/src/protocol/types.ts:1-213` (TS source of truth today),
  `pi-extension/src/protocol/codec.ts:3-18` (drifted registry).

<!-- /agile-workflow:refactor-design fills in the codegen approach, schema
language choice, and per-unit test approach. -->
