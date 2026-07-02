---
id: epic-bold-generated-protocol
kind: epic
stage: done
tags: [refactor, bold, pi-extension, app, relay, cockpit]
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# One protocol, generated three times — not handwritten in four places

## Thesis
The wire is the single source of truth. Define it once; generate TypeScript,
Dart, and Rust from it. Drift becomes impossible by construction — the generator
*is* the contract test. This is the foundation that makes every other bold
reconception cheaper and safer.

## Lens
Unification (with Generated Contracts)

## Impact
The protocol is currently a pile of handwritten mirrors: TS
(`pi-extension/src/protocol/types.ts`), Dart (`app/lib/protocol/protocol.dart`,
1313 lines), Rust (`relay/src/protocol/outer.rs` + `rooms.rs`), plus a *fourth*
private NUL-prefix RPC between cockpit and pi-extension (`\x00remote-pi-ctrl:`
mirrored in `cockpit/lib/app/cockpit/data/rpc/pi_rpc_process.dart:372-385` and
`pi-extension/src/index.ts:146`). Drift is already biting: `codec.ts`'s
`SERVER_TYPES` registry omits `user_message`, `compaction`, `action_ok`,
`action_error`, `models_list`; `relay_client.ts`'s `RoomMeta` omits
`thinking`/`working` that `index.ts` stores; Dart compensates by reading
`thinking` top-level *or* nested under `meta`. Every wire change is a coordinated
hand-edit across 3-4 languages with no compile-time signal — the direct cause of
"annoying to bugfix."

A single schema defines every wire message across all three transports (app↔pi
chat/control, cross-PC `pi_envelope`, cockpit↔pi control RPC) and codegenerates
the TS unions + validators, Dart sealed classes + `fromJson`, Rust serde structs,
and codec registries. Every message becomes self-describing (carries canonical
session id, turn id, type). The NUL-prefix string RPC folds into the same schema.

## Cost
The real investment is the codegen pipeline, and the feasibility hinge is
**Dart sealed-class codegen** — if clean Dart codegen isn't feasible the
foundation's shape changes. Transition is incremental: generate alongside the
hand mirrors, swap consumers one message at a time. Hardest non-codegen part:
the cockpit control RPC is a separate transport (Pi custom events, not relay),
so the schema must span two transports.

## Child features (riskiest first)
- **epic-bold-generated-protocol-dart-codegen** *(riskiest — design this first; the
  whole epic's shape depends on whether clean Dart sealed-class codegen is
  feasible)* — Dart codegen target: sealed `ClientMessage`/`ServerMessage`,
  `fromJson` narrowing, codec parity with TS. Absorbs today's hand mirror.
- epic-bold-generated-protocol-schema-source — the single canonical schema +
  validators; the one place a new wire message is added.
- epic-bold-generated-protocol-ts-codegen — TS unions + validators + codec
  registry generated; replaces `protocol/types.ts` + `protocol/codec.ts`.
- epic-bold-generated-protocol-rust-codegen — Rust serde structs for
  `OuterEnvelope`, `RoomMeta`, control frames; replaces hand structs in
  `relay/src/protocol/`, `rooms.rs`.
- epic-bold-generated-protocol-cockpit-control-rpc — fold the `\x00remote-pi-ctrl:`
  NUL-prefix string RPC into the generated schema; retire the magic prefix.

## Decomposition

Decomposition pre-existed (bold-refactor scan) — child features listed above in "Child features (riskiest first". Advanced to implementing via epic-design Phase 1.5 short-circuit.
