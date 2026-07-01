---
id: release-relay-0.2.0
kind: release
stage: quality-gate
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

### Binding-consistency warnings

binding_guard=warn epic_cohesion=phased. CONFLICTS(3) + INCOMPLETES(5), all
informational/non-halting — phased delivery where relay-tagged stories ship here
while multi-component parents (canonical-session, generated-protocol,
reachability-contract-state-machine) ship in v0.6.0. Same pattern as prior releases.
