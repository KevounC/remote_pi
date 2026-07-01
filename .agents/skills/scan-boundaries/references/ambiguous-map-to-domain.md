# Rule: Ambiguous Map To Domain

> Do not pass untyped `Record` / `Map` / `HashMap<String, Value>` / `Value` blobs deep into domain logic. Parse to a typed DTO at the boundary; domain code consumes the typed shape.

## Motivation

The fail-fast rule in [`.agents/rules/code-design.md`](../../../rules/code-design.md) says untrusted
data is validated at the *first boundary* and never passed as an ambiguous blob into business
logic. When a `HashMap<String, serde_json::Value>` or a TS `Record<string, unknown>` or a Dart
`Map<String, dynamic>` is handed to a domain function, the domain is forced to re-validate or
narrow at every use site — or worse, silently assumes a shape that may not hold. The fix is to
parse at the boundary into a typed DTO (Rust: `serde::Deserialize` into a struct; TS:
`unknown` + narrowing or a schema; Dart: a generated/typed DTO). This is behavior-preserving
when the parsed values are identical; it moves the validation from scattered use sites to one
boundary parse.

This rule is the *inbound* companion to `ad-hoc-wire-parse` (which is about the handler's own
parse). This rule fires when the already-parsed-but-untyped blob is *passed deeper*.

## Signals

A domain/core function signature or call site moving an untyped container into domain code:
- Rust: `fn handle(&mut self, payload: HashMap<String, Value>)` in a domain module
- Rust: `payload: &serde_json::Value` parameter in a function under `handlers/` that delegates
  to further domain logic without narrowing first
- TS: `function project(record: Record<string, unknown>)` in a domain/ projection module
- Dart: `void apply(Map<String, dynamic> json)` in a domain/entity or use-case

The distinguishing signal from `ad-hoc-wire-parse`: here the data has already been parsed *once*
(into the ambiguous container) and is being *passed deeper* rather than navigated at the
handler. Both can fire on the same call chain.

## Before / After

### Synthetic example: blob passed to domain (in a domain/core path)

**Before (violation):**
```rust
// in a relay domain/core module (NOT a handler — handlers are excluded from this rule)
fn apply_room_meta(&mut self, payload: &serde_json::Value) {   // ambiguous blob into domain logic
    let name = payload.get("name").and_then(|v| v.as_str()).unwrap_or("main");
    // ... domain reasoning about `name` ...
}
```

**After:**
```rust
// parse at the boundary into the generated typed frame
let frame: RoomMetaUpdateFrame = serde_json::from_value(payload.clone())?;
self.apply_room_meta(&frame);   // domain takes the typed DTO
fn apply_room_meta(&mut self, frame: &RoomMetaUpdateFrame) {
    let name = frame.name.as_deref().unwrap_or("main");
}
```

### From this codebase: borderline (needs analysis)

`relay/src/handlers/connection_actor.rs:94` previously held `last_rooms_resp: HashMap<String, String>`.
That file is a **handler** (excluded from this rule per Scope) and the map is typed (`String`→`String`),
so it is doubly not a violation. Cited only to clarify the typed-map exemption below.
This is a *typed* map (String→String), not an ambiguous blob, so it is likely a legitimate
cache of already-narrowed values. Mark **low** confidence and let the scanner note it as
"verify the values are narrowed before reaching here" rather than a fix. Do not auto-emit a
finding for typed `HashMap<String, String>` — only for `HashMap<String, Value>` / `Value` /
`Record<string, unknown>` / `Map<String, dynamic>`.

## Exceptions

- **Typed maps are not violations** — `HashMap<String, String>`, `Map<String, MyDto>`,
  `Record<string, number>` carry typed values and are fine. Only *untyped-value* containers
  (`Value`, `unknown`, `dynamic`, `any`) are violations.
- **Opaque forwarding caches** — a `HashMap<String, Value>` that stores frames for later
  opaque forwarding (never interpreted) is exempt per `ad-hoc-wire-parse`'s opaque-forwarding
  exception. Verify via the same signal: the cached value is never `.get()`-navigated for its
  interior fields.
- **Projection/replay code that materializes a typed event** — `app/lib/domain/transcript/`
  projection code may transiently hold a `Map` while hydrating a typed `TranscriptEvent`, as
  long as it narrows before any domain decision. Medium confidence; needs analysis.
- **Test fixtures and generated code** — skip.

## Scope

- Applies to: domain/core paths in all four code subprojects (see `domain-imports-infra` Scope)
- Does NOT apply to: composition roots, test fixtures, generated code, `site/`
