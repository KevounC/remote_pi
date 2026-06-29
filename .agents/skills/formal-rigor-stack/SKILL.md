---
name: formal-rigor-stack
description: Remote Pi formal-methods and rigorous protocol architecture reference. Read when discussing TLA+, Quint, Alloy, Apalache, Protobuf/Buf, protocol schema generation, cross-language contract tests, mobile framework choice, React Native/Expo vs Flutter, reliable delivery, mesh membership, or rigorous reimplementation of Remote Pi.
user-invocable: false
updated: 2026-06-28
---

# Formal Rigor Stack Reference

Scope: Remote Pi protocol/state-machine redesign and rigorous reimplementation planning.

Primary research brief: `.research/analysis/briefs/rigorous-reimplementation-stack.md`.

## Default recommendation

Do not rewrite code first. Rewrite the specification surface first:

1. Reconcile `PROTOCOL.md` with current implementation/plan semantics.
2. Model dynamic behavior in TLA+ or Quint.
3. Model relational identity/membership/address invariants in Alloy 6.
4. Add property/conformance tests in Rust/TypeScript/mobile.
5. Choose one schema/IDL source of truth before broad cross-language changes.

## Current delivery semantics to preserve

`PROTOCOL.md` and the agent-network skill now describe current reliable-delivery semantics: the broker does not emit `busy` for new work, and a peer mid-turn still receives the message for a later turn. Any model or rewrite must preserve no retry-on-busy semantics unless intentionally reversing the product decision.

## Tool placement

| Tool | Use for Remote Pi |
|---|---|
| TLA+ + TLC | Conservative primary for agent-network delivery, ACK/timeout, reconnect, room/session state, cross-PC forwarding, and mesh update races. |
| PlusCal | Entry point for algorithm-shaped broker/relay specs that translate to TLA+. |
| Quint | More ergonomic TLA-like language; candidate if developer/agent readability matters more than ecosystem maturity. |
| Apalache | Add for SMT-backed bounded/inductive checking after TLA+/Quint specs exist or TLC hits state explosion. |
| Alloy 6 | Identity graph, owner/pi/app key relations, membership, address uniqueness, revocation, anti-spoof, legal routing topology. |
| Dafny/F*/Lean/Coq | Defer; only consider for a tiny verified protocol/crypto kernel. |

## What to model first

1. **Agent-network delivery**
   - Opaque addresses: `<cwd>@<name>` and optional `<pc>:` prefix.
   - Unicast vs broadcast/multicast.
   - `received | denied | timeout`, reply correlation by `re`, no self-send.
   - Mid-turn delivery queues rather than busy-drop.

2. **Mobile remote-coding state**
   - Authoritative snapshots + idempotent commands + replayable deltas + reconnect hydration.
   - App background/resume as nondeterministic socket loss.
   - `working` convergence false after success, error, abort, reconnect, and session replacement.
   - Responses bound to `(peer, room/session, command id)`.

3. **Mesh membership and anti-spoof**
   - Owner-key / Pi-key / App-key roles.
   - Owner-signed monotonic `mesh_versions`.
   - Revocation/self-revoke.
   - Relay-side membership authorization and broker-side prefix anti-spoof.

4. **Relay backpressure**
   - Current relay uses unbounded Tokio mpsc senders; any high-volume producer needs bounded/dedup/drop semantics.

## Schema source of truth

Preferred for rigorous rewrite: **Protobuf + Buf**.

Why:
- one IDL for Rust/TypeScript/Dart generation;
- linting and breaking-change checks;
- cleaner compatibility discipline than handwritten mirrors.

Caveat: schemas do not encode temporal/session/freshness invariants. Keep TLA+/Quint/Alloy and property tests.

Incremental option: keep JSON wire but add JSON Schema/TypeBox/Zod/AJV plus generated Rust/Dart types. This is lower migration cost but weaker as a cross-language SSOT.

## Mobile framework position

Flutter is technically appropriate and should not be dismissed:
- mature cross-platform mobile UI;
- Dart is statically typed;
- existing Remote Pi investment is high;
- platform channels and state restoration exist.

But for a greenfield rewrite, **React Native/Expo TypeScript deserves serious evaluation** because it aligns mobile with the TypeScript extension/site and the operator's preferred agentic coding surface.

Do not assume framework choice solves swallowed-message or background-socket bugs. iOS/Android background behavior must be modeled independently: mobile clients need snapshots, retries, durable command ids, stale-state rendering, and reconnect hydration.

## Decision heuristics

- Need fastest rigorous improvement: keep Flutter, fix protocol docs, add TLA+/Alloy specs and cross-language tests.
- Need greenfield operator-friendly stack: Rust relay/core + TypeScript extension + React Native/Expo mobile.
- Need strongest platform lifecycle integration: native Swift/Kotlin, but expect much higher cost.
- Need maximum formal core reuse: Rust core with mobile FFI, but only after a spike proves build/release complexity acceptable.

## Review checklist for protocol changes

- [ ] Did `PROTOCOL.md` change before code semantics changed?
- [ ] Is there a TLA+/Quint or Alloy update for changed state semantics?
- [ ] Did schema/IDL/generation update if wire shape changed?
- [ ] Are golden vectors shared across Rust/TS/mobile?
- [ ] Are Rust `proptest` and TS `fast-check` properties updated where applicable?
- [ ] Does mobile reconnect from authoritative snapshots, not sticky UI booleans?
- [ ] Does every `working: true` path converge false?
- [ ] Are address strings treated as opaque routing keys?
