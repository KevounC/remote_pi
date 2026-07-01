# Rule: Handwritten Wire DTO Duplicates Generated

> A struct/class/interface defining a wire frame shape must import or re-export the generated DTO, not re-declare the same fields.

## Motivation

When a wire frame shape exists in `protocol/generated/` and a non-generated file re-declares a
struct with the same fields, the two definitions can drift: a schema change updates the generated
DTO but the handwritten mirror stays stale, and the wire silently diverges between the two. The
fix is to import/re-export the generated type. The correct thin-facade pattern already exists in
this repo and is exempted below.

The principle is in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Generated or
inferred contracts.

## Signals

- A `struct`/`class`/`interface` in a non-generated file whose fields match a generated DTO's
  fields (same names, same types), declared independently rather than `pub use`/`import`'d.
- Especially: a handwritten `struct RoomMetaUpdateFrame` in `relay/src/` when
  `relay/src/protocol/generated/control.rs` already defines one.

## Before / After

### From this codebase: the correct facade pattern (keep this — NOT a violation)

**Current (correct) — `relay/src/protocol/frame.rs`:**
```rust
pub use crate::protocol::generated::control::RelayControlFrame;
pub use crate::protocol::generated::cross_pc::PiEnvelopeFrame;
use crate::protocol::generated::frame::{RELAY_INBOUND_FRAME_TYPES, RelayInboundFrame};
```
This file is a **thin re-export facade** — it consumes the generated types and adds a
`DecodedRelayFrame` enum that *composes* them, with a documented `MalformedPiEnvelope(Value)`
escape hatch. It does NOT re-declare the generated fields. This is the correct pattern; do not
flag `frame.rs` or any file whose types are `pub use`/re-exports of generated types.

### Synthetic: violation

**Before (violation):**
```rust
// relay/src/handlers/foo.rs — handwritten, duplicates generated
struct RoomMetaUpdateFrame {
    room_id: String,
    meta: RoomMeta,   // same fields as generated::control::RoomMetaUpdateFrame
}
```

**After:**
```rust
use crate::protocol::generated::control::RoomMetaUpdateFrame;   // single source
```

## Exceptions

- **Re-export facades** — files whose types are `pub use generated::...` / `export { ... } from
  "./generated/..."` are the correct pattern; never flag. The signal that distinguishes a facade
  from a violation: the file does not re-declare fields, only re-exports or composes.
- **Documented temporary islands** — `app/lib/protocol/control_frames.dart` is hand-maintained
  *with a documented reason* ("Relay control/presence/rooms frames are not yet in the schema IR").
  This is exempted under `undocumented-protocol-island`, not here — but if it IS documented, do
  not flag here either.
- **Adapter/codec types** — a type that bridges wire and domain (e.g. a domain entity that
  *contains* a wire field but is not itself a wire frame) is not a duplicate; the scanner verifies
  the handwritten type is claiming to *be* a wire frame, not just consuming one.
- **Test fixtures and generated code** — skip.

## Scope

`relay/src/protocol/**` (non-generated), `relay/src/handlers/**` (non-test), `relay/src/peers/**`
(non-test), `pi-extension/src/protocol/**` (non-generated), `pi-extension/src/transport/**`
(non-test), `app/lib/protocol/**` (non-test, non-generated). Does NOT apply to generated code,
tests, `site/`.
