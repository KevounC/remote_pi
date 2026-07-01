---
id: release-relay-0.2.0
kind: release
stage: released
tags: []
parent: null
depends_on: []
release_binding: relay-0.2.0
gate_origin: null
created: 2026-07-01
updated: 2026-07-01
---

# Release relay-0.2.0

Third gate-enabled release; pairs with app-v1.2.0 (the relay-auth domain-separation
wire change lands here). Binds the relay-attributed bold-refactor work: relay-typed-actor
epic (control-handlers, frame-dispatch, registry-split) whole, canonical-session
relay-opaque-targeting feature whole, generated-protocol rust-codegen feature whole,
plus reachability-contract-state-machine-step-4 (parent is multi-component → repo-level).

## Bound items

### Active done items (27)
- epic-bold-relay-typed-actor (epic)
- epic-bold-relay-typed-actor-control-handlers (feature) + 6 steps
- epic-bold-relay-typed-actor-frame-dispatch (feature) + 5 steps
- epic-bold-relay-typed-actor-registry-split (feature) + 5 steps
- epic-bold-canonical-session-relay-opaque-targeting (feature) + 4 steps
- epic-bold-generated-protocol-rust-codegen (feature) + 5 steps
- epic-bold-reachability-contract-state-machine-step-4 (story — parent is repo-level)

### Archived stubs late-bound
(none)

## Gate runs

### gate-cruft (2026-07-01) — 2 findings (0 high, 1 medium, 1 low)

- Medium: unused ActorDispatch::Close variant behind #[allow(dead_code)] (connection_actor.rs:28)
- Low: PresenceTransitions single-impl pass-through trait (registry.rs:64)
2 items → backlog (non-blocking). Tighter grep-first scoping avoided compaction.

### gate-docs (2026-07-01) — 1 finding (0 high, 0 medium, 1 low)

- Low: relay/CLAUDE.md logging guidance references info_span! but handlers use info!/warn!/error! directly (:30)
1 item → backlog. Docs gate SUCCEEDED this run (tighter grep-first prompt — no compaction; previously failed twice on app).

(populated by remaining gates as they complete)

### gate-security (2026-07-01) — 4 findings (0 critical, 0 high, 3 medium, 1 low)

- Medium: auth challenge step has no timeout — pre-auth sockets held indefinitely (peer.rs:83)
- Medium: data-plane outbound queues unbounded — memory growth via slow recipient (connections.rs:15)
- Medium: subscription target map retains empty entries — memory growth via churn (subscriptions.rs:54)
- Low: frame decoder parses JSON before size checks — avoidable allocation on oversized frames (frame.rs:38)
4 items → backlog (non-blocking). The signing-oracle fix from app-v1.2.0 is NOT re-flagged (resolved).

(populated by refactor/tests/patterns as they complete)

### gate-patterns (2026-07-01) — 5 pattern candidates discovered

5 reusable shapes (3+ occurrences each): typed-frame-dispatch-chain, control-frame-guard-and-execute-handlers, subscriber-fanout-with-empty-short-circuit, shared-reverse-index-subscription-graph, generated-protocol-boundary-adapter. Pattern-skill authoring deferred (separate artifact under .agents/skills/patterns/). Recorded for traceability.

(populated by refactor/tests as they complete)

### gate-refactor (2026-07-01) — 4 findings (0 high, 4 medium, 0 low) from 3 libraries

- Medium: mesh membership blob parsed through serde_json::Value (pi_forward.rs:106) — same site scan-boundaries flagged
- Medium: protocol parser reads process env directly (outer.rs:34)
- Medium: control handler repeats generated frame type strings (control.rs:68)
- Medium: relay outbound control frames undocumented hand-maintained island (registry_event_publisher.rs:49)
4 items → backlog (non-blocking). boundaries=2, lifecycle=0, protocol-contract=2.

### gate-tests (2026-07-01) — 6 gaps (5 critical, 0 high, 1 medium) from 206 ACs (200 covered)

5 CRITICAL blocking, all clustered on to_room in cross-PC pi-envelope forwarding:
- to_room missing/empty not tested as bad_envelope (pi_forward.rs:167)
- valid to_pc/to_room frames uncoverable: PiEnvelopeFrame omits to_room (cross_pc.rs:20)
- cross-PC forwarding covered as peer-wide fanout, not room-targeted (pi_forward.rs:186)
- pi_envelope_in delivery doesn't test to_room metadata (pi_forward.rs:181)
- unknown destination room not covered as correlated offline (pi_forward.rs:186)
1 medium (relay heartbeat first-tick partial) → backlog.

**NOTE**: the 5 critical gaps trace to an unimplemented feature, not just missing tests.
The story relay-opaque-targeting-step-1 was approved claiming to_room parsing + bad_envelope,
but handle_pi_envelope only checks to_pc.is_empty() and PiEnvelopeFrame has no to_room field.
Tests assert to_room is ABSENT. Resolving requires implementing to_room routing + the tests.

## Blocking findings (5) — must resolve before ship

5 critical tests-gate gaps (to_room routing). Per gate_finding_routing (critical→implementing, blocking).

### Binding-consistency warnings

binding_guard=warn epic_cohesion=phased. CONFLICTS(3) + INCOMPLETES(5), all
informational/non-halting — phased delivery where relay-tagged stories ship here
while multi-component parents (canonical-session, generated-protocol,
reachability-contract-state-machine) ship in v0.6.0. Same pattern as prior releases.

## Shipped items

Bodies live on disk (retain-bodies) and in git history.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| epic-bold-relay-typed-actor | The relay connection is a typed-frame actor, not a JSON switch | epic | — | 5cbf5b1 |
| epic-bold-canonical-session-relay-opaque-targeting | Canonical session — relay opaque session targeting | feature | — | 5cbf5b1 |
| epic-bold-generated-protocol-rust-codegen | Generated protocol — Rust serde codegen target | feature | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-control-handlers | Relay typed actor — typed control handlers | feature | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-frame-dispatch | Relay typed actor — typed-frame dispatch (riskiest — design first) | feature | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-registry-split | Relay typed actor — PeerRegistry split | feature | — | 5cbf5b1 |
| epic-bold-canonical-session-relay-opaque-targeting-step-1 | Step 1: Add explicit cross-PC room target parsing | story | — | 5cbf5b1 |
| epic-bold-canonical-session-relay-opaque-targeting-step-2 | Step 2: Replace peer-wide fanout with room-targeted registry forwarding | story | — | 5cbf5b1 |
| epic-bold-canonical-session-relay-opaque-targeting-step-3 | Step 3: Preserve transport-error semantics and inbound target metadata | story | — | 5cbf5b1 |
| epic-bold-canonical-session-relay-opaque-targeting-step-4 | Step 4: Lock the opaque relay boundary with regression tests and comments | story | — | 5cbf5b1 |
| epic-bold-generated-protocol-rust-codegen-step-1 | Step 1: Add the Rust generator backend over the shared protocol IR | story | — | 5cbf5b1 |
| epic-bold-generated-protocol-rust-codegen-step-2 | Step 2: Generate `OuterEnvelope` and preserve the opaque payload parser | story | — | 5cbf5b1 |
| epic-bold-generated-protocol-rust-codegen-step-3 | Step 3: Generate auth and relay control-frame serde types | story | — | 5cbf5b1 |
| epic-bold-generated-protocol-rust-codegen-step-4 | Step 4: Generate `RoomMeta` / `RoomMetaPatch` and swap room state consumers | story | — | 5cbf5b1 |
| epic-bold-generated-protocol-rust-codegen-step-5 | Step 5: Generate cross-PC and mesh wire types, then add parity checks | story | — | 5cbf5b1 |
| epic-bold-reachability-contract-state-machine-step-4 | Step 4: Add the Rust Reachability projection module for relay heartbeat policy | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-control-handlers-step-1 | Step 1: Add the typed control-handler dispatch shell | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-control-handlers-step-2 | Step 2: Type the auth challenge and hello room bootstrap handler | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-control-handlers-step-3 | Step 3: Factor the duplicated presence/rooms subscription graph | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-control-handlers-step-4 | Step 4: Move presence and rooms control frames into typed actor handlers | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-control-handlers-step-5 | Step 5: Move room metadata updates into a typed actor handler | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-control-handlers-step-6 | Step 6: Consume generated mesh-membership DTOs at the HTTP handler boundary | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-frame-dispatch-step-1 | Step 1: Introduce the typed relay frame decode boundary | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-frame-dispatch-step-2 | Step 2: Extract the authenticated connection actor shell | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-frame-dispatch-step-3 | Step 3: Route app↔Pi outer envelopes through the typed actor | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-frame-dispatch-step-4 | Step 4: Route cross-PC `pi_envelope` through typed dispatch | story | — | 5cbf5b1 |
| epic-bold-relay-typed-actor-frame-dispatch-step-5 | Step 5: Replace the raw control-frame switch with exhaustive typed dispatch | story | — | 5cbf5b1 |
| gate-tests-pi-envelope-in-to-room | Successful pi_envelope_in delivery does not test required to_room metadata | story | — | 5cbf5b1 |
| gate-tests-to-room-missing-bad-envelope | Missing/empty to_room is not tested as bad_envelope | story | — | 5cbf5b1 |
| gate-tests-to-room-room-targeted-delivery | Cross-PC forwarding is still covered as peer-wide fanout, not room-targeted delivery | story | — | 5cbf5b1 |
| gate-tests-to-room-valid-frame-authorization | Valid to_pc/to_room frames cannot be covered because generated cross-PC DTOs omit to_room | story | — | 5cbf5b1 |
| gate-tests-unknown-destination-room-offline | Unknown destination room is not covered as correlated offline | story | — | 5cbf5b1 |
