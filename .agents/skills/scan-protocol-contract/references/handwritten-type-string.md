# Rule: Handwritten Type String Duplicates Registry

> A wire message-type or frame-type literal string must not be written by hand when a generated `as const` registry or generated enum already defines it.

## Motivation

Remote Pi generates a single source of truth for protocol types in each subproject:
`pi-extension/src/protocol/generated/protocol.generated.ts` exports `relayControlTypes` (and
`CLIENT_MESSAGE_TYPES`, `SERVER_MESSAGE_TYPES`) as `as const` registries with derived union types
(`RelayControlType`, `ClientMessageType`, `ServerMessageType`); `relay/src/protocol/generated/`
carries the Rust equivalents. When a handler writes the literal `"room_meta_update"` or
`"peer_online"` instead of referencing the constant, the type string is re-enumerated: a schema
rename won't surface as a compile error at that site, and the handwritten string can silently
drift from the canonical value.

The principle is in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Single source of truth.

## Signals

- A literal string `"peer_online"`, `"peer_offline"`, `"presence_check"`, `"room_meta_update"`,
  `"pi_envelope"`, etc. in handler/transport/UI code, where that string is also a value in the
  generated registry (`SERVER_MESSAGE_TYPES`, `RELAY_INBOUND_FRAME_TYPES`, etc.).
- In TS: `relay?.sendControl({ type: "room_meta_update", ... })` when `room_meta_update` is in
  the generated `as const` registry.
- In Rust: matching `"presence_check"` as a literal where `RelayControlFrame` variants are
  generated.

## Before / After

### From this codebase: the generated source of truth (use it)

**Current (correct target) — `pi-extension/src/protocol/generated/protocol.generated.ts`:**
```ts
export const relayControlTypes = [ "hello", "auth", "challenge", "subscribe_presence",
  "presence_check", "presence", "peer_online", "peer_offline", "subscribe_rooms",
  "rooms_check", "rooms", "room_announced", "room_ended", "room_meta_update" ] as const;
export type RelayControlType = (typeof relayControlTypes)[number];
```

### From this codebase: violation (TS — the literal duplicates `relayControlTypes`)

**Before — `pi-extension/src/extension/relay_transport.ts:255`:**
```ts
relay?.sendControl({ type: "room_meta_update", room_id: roomId, meta: patch });
//                    ^^^^^^^^^^^^^^^^^^ literal duplicating a value in relayControlTypes
```
and `pi-extension/src/transport/relay_client.ts:48`:
```ts
type: "room_meta_update";   // literal in a handwritten interface duplicating RelayControlType
```

**After:**
```ts
import { relayControlTypes } from "../protocol/generated/protocol.generated.js";
// verify the exact exported name (relayControlTypes) and index into it, or use the
// RelayControlType union; do NOT invent a constant name — read the generated module first
relay?.sendControl({ type: relayControlTypes[/* ROOM_META_UPDATE */], room_id: roomId, meta: patch });
```
The scanner MUST verify the generated registry (`relayControlTypes`) actually contains the
literal before flagging, and MUST cite the real exported name — not an invented one.

### IMPORTANT: this rule is language-conditional, not blanket

The `relayControlTypes` registry exists ONLY in the pi-extension TS generated file. The Dart
generated file (`app/lib/protocol/generated/protocol.g.dart`) does NOT contain
`peer_online`/`presence_check`/`room_meta_update` — those relay control frames are a documented
temporary island in Dart (see `undocumented-protocol-island`). So a `"peer_online"` literal in
`app/lib/protocol/control_frames.dart` is NOT a `handwritten-type-string` violation in Dart —
it is a documented-island exception. Only flag a literal when the SAME subproject's generated
registry actually contains it.

## Exceptions

- **Test code asserting the exact wire shape** — a contract test that asserts `v["type"] ==
  "peer_online"` is *verifying* the canonical value and may legitimately use the literal to catch
  drift. Skip test files.
- **Generated code** — the generated registry itself contains the literals; skip `generated/`.
- **Forward-compat parsing** — a parser that does `switch (j['type']) { 'peer_online' => ...
  default => null }` to tolerate unknown future types may use literals if it is the *boundary*
  decode; but prefer deriving the cases from the registry. Mark medium; needs analysis.
- **String not in any registry** — if the literal is not a value in any generated registry, it is
  not a duplication; emit nothing.
- **Boundary decoders / malformed-envelope escape hatches** — `relay/src/protocol/frame.rs`
  contains the literal `"pi_envelope"` at the decode boundary while also using generated
  `RELAY_INBOUND_FRAME_TYPES`; this is the boundary probe + `MalformedPiEnvelope(Value)` escape
  hatch, not a duplication. Skip the boundary decode site in `frame.rs`.

## Scope

`pi-extension/src/transport/**`, `pi-extension/src/extension/**`, `pi-extension/src/session/**`
(non-test), `app/lib/protocol/**` (non-test, non-generated), `app/lib/data/**` (non-test),
`relay/src/handlers/**`, `relay/src/peers/**` (non-test). Does NOT apply to generated code,
tests, `site/`.
