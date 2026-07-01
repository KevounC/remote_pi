# Rule: Frame Discriminator Re-enumerated

> A `switch`/`match`/validator over frame types must derive its cases from the canonical registry, not re-list the type strings.

## Motivation

When a handler does `switch (type) { "presence_check" => ..., "room_meta_update" => ... }` and a
new frame type is added to the schema, the generated registry gains the variant but this switch
silently falls through to `default`/`null` — the new frame is unhandled with no compile error.
The fix is to derive an exhaustive union from the registry (TS: `typeof REGISTRY[number]`; Rust:
a generated enum with a `match` that the compiler checks for exhaustiveness; Dart: a `sealed`
class hierarchy). This is the "derive types, validation, dispatch, and display from one registry"
rule from [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Single source of truth.

## Signals

- A `switch (x) { "peer_online" => ..., "peer_offline" => ... }` (Dart) /
  `match x { "peer_online" => ... }` (Rust) / `switch (x) { case "peer_online": }` (TS) that
  re-lists frame type strings present in a generated registry.
- A validator `isRelayControlFrame(type) { return ["presence_check", ...].includes(type) }` that
  re-enumerates instead of deriving from the generated list.
- Especially: a `default => null` / `_ => ()` arm that silently drops unhandled types, where an
  exhaustive generated enum would force a compile error on addition.

## Before / After

### From this codebase: the generated exhaustive shape (target)

**Current (correct) — `relay/src/protocol/generated/frame.rs`:**
```rust
pub enum RelayInboundFrame {
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
}
// generated Deserialize parses the "type" discriminator into the typed enum
```
Handlers `match` on `RelayInboundFrame::Control(c) => ...` and the compiler verifies
exhaustiveness — a new variant added to the schema surfaces as a non-exhaustive match error.

### From this codebase: violation (handwritten re-enumeration)

**Before — `app/lib/protocol/control_frames.dart:18-92` (re-enumeration inside the documented island):**
```dart
static ControlInbound? tryFromJson(Map<String, dynamic> j) {
  return switch (j['type']) {
    'peer_online' => PeerOnline(peer: j['peer'] as String),    // re-listed literals
    'peer_offline' => PeerOffline(...),
    'presence' => PresenceSnapshot(...),
    _ => null,                                                  // silently drops unknown
  };
}
```
A new control frame type added to the schema would fall through to `_ => null` with no compile
error. **This is inside a documented temporary island** (documented at `protocol.dart:4`: "Relay
control/presence/rooms frames are not yet in the schema IR"). Per the cross-rule delineation in
`SKILL.md`, a documented island suppresses `discriminator-reenumerated` and `handwritten-type-string`
for its literals/switch — the re-enumeration is a symptom of the not-yet-migrated island, and the
fix is migration (behavior-changing), which routes through story design as its own work. Emit
nothing here; track migration via `undocumented-protocol-island` only if the island loses its
documentation.

**After (via schema migration):**
```dart
// generated: sealed class ControlInbound with variants; tryFromJson derives cases
final c = ControlInbound.fromJson(j);   // exhaustive; new type is a compile-time addition
```

## Exceptions

- **Generated code** — the generated `Deserialize`/`tryFromJson` itself switches on literals to
  build the typed value; that is the source of truth, skip `generated/`.
- **Forward-compat boundary decode** — a parser that intentionally returns `null`/`unknown` for
  unrecognized types to tolerate schema evolution *may* legitimately re-list known types, but
  should derive the known set from the registry. Mark medium; needs analysis.
- **Test code** — skip test files.
- **Documented islands** — if the re-enumeration is in a documented temporary island, the
  *island* is the finding (under `undocumented-protocol-island` if undocumented), not the
  re-enumeration per se; avoid double-flagging.

## Scope

`relay/src/handlers/**` (non-test), `relay/src/peers/**` (non-test), `relay/src/protocol/**`
(non-generated), `pi-extension/src/transport/**`, `pi-extension/src/session/**` (non-test),
`app/lib/protocol/**` (non-test, non-generated), `app/lib/data/**` (non-test). Does NOT apply to
generated code, tests, `site/`.
