# Rule: Ad-hoc Wire Parse In Handler

> Handler/business code must consume a typed frame, not parse wire payloads into `serde_json::Value` / ad-hoc maps and navigate them with `.get()`/`as_array()`.

## Motivation

Remote Pi generates typed protocol frames in every code subproject (`relay/src/protocol/generated/`,
`pi-extension/src/protocol/generated/`, `app/lib/protocol/generated/`) from one schema source —
the bold-refactor `generated-protocol` epic's single-source-of-truth wire. When a handler parses
a wire payload into `serde_json::Value` and navigates it with `.get("members")` /
`.as_array()`, it silently re-derives the wire shape in business logic: schema changes don't
surface as compile errors, and the boundary check (fail-fast) is skipped.

The principle is in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Generated or
inferred contracts + Fail fast at boundaries.

## IMPORTANT: distinguish "generated type exists" from "DTO should exist"

The right fix depends on whether a typed frame already exists for the payload being parsed:

- **If a generated typed frame exists** for the payload → the fix is to deserialize into it. This
  is higher confidence and closer to behavior-preserving (the serialized form is byte-identical;
  only the in-memory representation changes). **Verify the generated type's fields actually match
  the payload before asserting this** — do not assume a generated type exists for every payload.
- **If NO generated type exists** (the payload is an interior blob of a forwarded envelope, or
  an untyped domain payload) → the fix is to *add* a typed DTO. This is **behavior-changing**
  (errors surface earlier, malformed input is rejected instead of silently skipped) and must
  route through story/feature design, not refactor-design. Mark medium confidence; the finding
  proposes the DTO, the design pass decides the shape.

The scanner must check which case applies before assigning confidence. Asserting a generated
type exists when it does not is a fabrication.

## Signals

In handler/business code:
- `let v: serde_json::Value = serde_json::from_str(...)` followed by `v.get("...").as_...()`
- `parsed.get("members").and_then(|v| v.as_array())` style navigation of a wire payload
- `HashMap<String, serde_json::Value>` used to hold a wire frame that has a generated type
- `json!({"type": "peer_online", ...})` constructed in business logic instead of a typed frame

## Before / After

### From this codebase: the generated typed frame exists (use it) — high confidence

**Current (correct target) — `relay/src/protocol/generated/frame.rs`:**
```rust
pub enum RelayInboundFrame {
    Control(RelayControlFrame),
    PiEnvelope(PiEnvelopeFrame),
}
// generated Deserialize impl parses the "type" discriminator and yields a typed enum
```
Handlers should `let frame: RelayInboundFrame = serde_json::from_str(&text)?;` and `match` on
the variant — the discriminator logic already lives in the generated code.

### From this codebase: NO generated type exists — medium confidence (propose a DTO)

**Before — `relay/src/handlers/pi_forward.rs:106-119`:**
```rust
let parsed: serde_json::Value = match serde_json::from_slice(&envelope.blob) {
    Ok(v) => v,
    Err(err) => { /* continue */ }
};
let Some(members_arr) = parsed.get("members").and_then(|v| v.as_array()) else { continue; };
let set: HashSet<String> = members_arr
    .iter()
    .filter_map(|m| m.get("remote_epk").and_then(|v| v.as_str()).map(String::from))
    .collect();
```
The parsed payload is `envelope.blob` — the *interior* of a `PiEnvelopeFrame`. **There is no
generated type for this `members` payload** (`PiEnvelopeFrame` is `{to_pc, envelope}`, not
`{members}`; `relay/src/protocol/generated/` has no `members` frame). So the fix is NOT "use the
existing generated type" — it is "add a typed DTO for the mesh-members blob." That is
behavior-changing (the `continue` on parse error becomes a typed deserialize error path; the
filter-map over malformed members changes), so this finding is **medium confidence** and routes
through story design, not refactor-design.

**After (proposed, via a design pass):**
```rust
// a new generated/authored typed DTO for the members payload
let parsed: MeshMembersBlob = match serde_json::from_slice(&envelope.blob) {
    Ok(f) => f,
    Err(err) => { /* error path designed explicitly */ }
};
let set: HashSet<&str> = parsed.members.iter().map(|m| m.remote_epk.as_str()).collect();
```

## Exceptions

- **Opaque forwarding** — code that routes an envelope *unchanged* to another peer (e.g. a relay
  forwarding a `pi_envelope` blob it never interprets) may hold the payload as raw bytes/`Value`
  because it is not consuming the payload's meaning, only its destination. The signal that
  distinguishes opaque forwarding from a violation: the code **never calls `.get()`/`.as_*()` on
  the payload's interior fields**. Reading only a top-level routing field (`to`, `from`, `id`)
  is borderline — flag as low confidence for review. Reaching into `members`/`remote_epk`/etc.
  is a violation.
- **Malformed-frame handlers** — only the specific functions `handle_malformed_pi_envelope` and
  `dispatch_malformed_pi_envelope` (and functions whose name contains `malformed`) legitimately
  take `Value`, because they exist to reason about frames that *failed* typed deserialization.
  Do not flag those by name.
- **Test code, including `#[cfg(test)] mod tests`** — `let v: serde_json::Value =
  serde_json::from_str(...)` inside `#[tokio::test]` or `#[cfg(test)] mod tests` blocks (which
  live inside production files like `pi_forward.rs`) is a contract assertion on the exact wire
  shape and is correct. Skip any code inside a `#[cfg(test)]` module or a `tests/` directory.
- **Generated code** — `protocol/generated/**` contains `Value`-based deserializer impls by
  design (the generated `Deserialize` reads a `Value` then narrows). Skip generated files.

## Scope

- Applies to: `relay/src/handlers/**` (non-test), `relay/src/mesh/**` (non-test),
  `relay/src/peers/**` (non-test), `pi-extension/src/session/**` (non-test),
  `app/lib/data/**` (non-test)
- Does NOT apply to: `relay/tests/**`, `#[cfg(test)]` blocks, `protocol/generated/**`,
  composition roots, malformed-frame handlers (named above), opaque-forwarding paths
