---
id: release-v0.6.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: null
created: 2026-07-01
updated: 2026-07-01
---

# Release v0.6.0

Repo-level semver release (tag prefix `v`). Current shipped `v0.5.0`. Tag-only
release — no root version file to bump (consistent with v0.5.0; per-component
versions live in each subproject).

## Attribution

Per `.work/CONVENTIONS.md`, this release binds repo-level work: items with
multiple component tags (cross-component bold-refactor), `[refactor]`-tagged
step-children whose parent feature shipped in a component release, and
docs/research deliverables with no component code change. Single-component items
belong to their component release (already shipped: cockpit-v1.6.0, app-v1.2.0,
relay-0.2.0, extension-0.6.0).

## Bound items

111 active done items (all repo-level by attribution — zero stray
component-only items). The cross-component bold-refactor arc: canonical-session,
generated-protocol (schema-source + dart-codegen + cockpit-control-rpc),
reachability-contract, turn-state-machine (algebraic-state + late-attach +
projection-consumers), transcript-event-log (store + projection-derive +
hydration-replay), cockpit-workspace-projection, and the absorbed
session-isolation bugfixes.

### Excluded archived stubs (6)

All 6 unbound archived stubs are `status: superseded` with active replacements
already among the 111 bound items (e.g. `feature-session-isolation-wire-
discriminator` → `epic-bold-canonical-session-wire-discriminator`). Binding
superseded drafts would double-count. Excluded deliberately; documented for
auditability. (Matches v0.5.0's convention: it bound genuinely-done stubs, not
superseded ones.)

- bug-mobile-messages-swallowed-silently (superseded)
- feature-session-isolation-wire-discriminator (superseded → wire-discriminator)
- remote-pi-mobile-working-status-stuck (superseded)
- story-fix-cross-pc-bridge-late-attach-after-shutdown (superseded → sdk-session-projection-module)
- story-investigate-model-thinking-actions-after-session-replacement (superseded → sdk-session-projection-module)
- story-mobile-working-status-stuck (superseded → projection-consumers)

## Gate runs

### Tests gate — 2026-07-01

**Result: no coverage gaps.** Clean. Grep-first audit of acceptance criteria
across 111 bound items + the cross-component bundle; lifecycle/state-convergence
criteria are covered by targeted tests for stale Pi SDK/session replacement,
reconnect hydration, `working:false` convergence, WebSocket/relay teardown,
late attach, session history replay, room metadata projection. No
tautological/gamed tests. The component releases already caught the
lifecycle gaps; this bundle added no new untested surfaces.

### Security gate — 2026-07-01

2 findings (0 critical/high, 1 medium, 1 low). Skipped 13 exact duplicates from
the component releases' backlog. Both → backlog (non-blocking, pre-existing):
- `gate-security-pi-envelope-auth-scan-rate-limit` (medium) — relay `pi_envelope`
  authorization scans mesh storage without a negative cache/per-frame limiter.
- `gate-security-app-inbound-relay-frame-size-caps` (low) — app decodes inbound
  relay frames before size caps.

### Cruft gate — 2026-07-01

2 findings (2 medium). Tightly scoped to split-module + protocol-facade surfaces;
no compaction. Both → backlog (non-blocking):
- `gate-cruft-legacy-index-ports-adapter` (medium) — legacy index ports adapter
  is a compatibility shim surviving the module extraction.
- `gate-cruft-protocol-facade-stale-schema-ir-comment` (medium) — stale comment
  claiming relay-control frames aren't in the schema IR.

### Refactor gate — 2026-07-01

6 new findings (2 high, 4 medium, 0 low) from 3 loaded scan libraries
(`boundaries`, `lifecycle`, `protocol-contract`). Routing per
`gate_finding_routing`: 2 high → active implementing/blocking; 4 medium →
backlog/non-blocking. Checked 26 pre-existing `gate-refactor-*` items from
component gates and skipped duplicate signals.

- `gate-refactor-lifecycle-home-rename-controller` (high → **resolved**):
  Home rename dialog leaked its `TextEditingController`; wrapped the dialog
  await in `try/finally { controller.dispose(); }`. flutter analyze clean.
- `gate-refactor-protocol-pi-forward-type-literals` (high → **resolved**): Pi
  forward client handwrote the `pi_envelope`/`pi_envelope_in` discriminator
  literals; derived them from the generated `crossPcTypes` registry. typecheck
  + 44 transport tests green.
- `gate-refactor-lifecycle-app-router-floating-boot` (medium → backlog) — app
  bootstrap launches `ConnectionManager.boot` as an unguarded future.
- `gate-refactor-lifecycle-chat-bootstrap-floating` (medium → backlog) —
  ChatViewModel constructor discards bootstrap failures.
- `gate-refactor-lifecycle-connection-retry-floating` (medium → backlog) —
  retry timer discards the reconnect future.
- `gate-refactor-lifecycle-sync-service-floating-rebinds` (medium → backlog) —
  SyncService drops several lifecycle-sensitive async rebind/history futures.

### Docs gate — 2026-07-01

3 findings (2 high blocking, 1 medium). Grep-first prompt held. The 2 high
findings **resolved in-scope**; 1 medium → backlog:
- `gate-docs-protocol-source-stale-handwritten-claims` (high → **resolved**):
  `docs/ARCHITECTURE.md`, `SPEC.md`, `DECISIONS.md` described handwritten
  protocol mirrors as the de-facto source of truth; updated to reflect
  generated types are now canonical (this release shipped the codegen).
- `gate-docs-session-id-stale-absent-claim` (high → **resolved**): docs claimed
  `session_id` is absent on chat messages; updated to reflect canonical
  `session_id` is now required + fail-closed (canonical-session work shipped).
- `gate-docs-relay-ct-limit-1mib-stale` (medium → backlog) — stale ct-limit doc.

### Patterns gate — 2026-07-01

2 new reusable pattern skills documented (non-blocking by design):
- `snapshot-replay-event-mappers` — convert protocol snapshots/legacy payloads
  into canonical event lists before projection.
- `reachability-contract-projection` — project the shared reachability contract
  into each stack with clamped policy helpers.
Tracking item `gate-patterns-v0.6.0` (stage: done). Claude mirrors left
untracked (`.claude/skills/` is a compat mirror, not canonical — per AGENTS.md).

### Binding-consistency warnings

BINDING CONSISTENCY — release v0.6.0 (epic_cohesion: phased):
  • 0 CONFLICTs.
  • 1 INCOMPLETE — `story-to-room-sender-side-room-targeting` (unbound, stage:
    drafting) has parent `epic-bold-canonical-session` bound to v0.6.0.
    [informational under epic_cohesion: phased] — this is the deliberately-
    deferred to_room sender design story (see extension-0.6.0 release notes);
    it is not done, so it does not bind. Legitimate phased delivery.
