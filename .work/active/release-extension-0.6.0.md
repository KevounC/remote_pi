---
id: release-extension-0.6.0
kind: release
stage: quality-gate
tags: []
parent: null
depends_on: []
release_binding: extension-0.6.0
gate_origin: null
created: 2026-07-01
updated: 2026-07-01
---

# Release extension-0.6.0

Per-component semver release for the `pi-extension/` (Node/TypeScript Pi
extension). Tag prefix `extension-` (no `v`); current shipped `extension-0.5.4`.

## Attribution

Per `.work/CONVENTIONS.md`, this release binds only items with exactly one
component tag `pi-extension`. Cross-component bold-refactor work and
docs/research deliverables route to repo-level `v0.6.0`.

## Bound items

18 active done items (pi-extension-attributed).

### Active done items (18)

Epics/features:
- epic-bold-split-pi-extension-index
- epic-bold-generated-protocol-ts-codegen (feature)
- epic-bold-reachability-contract-pi-adapter (feature)
- epic-bold-split-pi-extension-index-cli-daemon-pairing-module (feature)
- epic-bold-split-pi-extension-index-composition-root (feature)
- epic-bold-split-pi-extension-index-owner-multiplexer-module (feature)
- epic-bold-split-pi-extension-index-relay-transport-module (feature)
- epic-bold-split-pi-extension-index-sdk-session-projection-module (feature)
- epic-bold-turn-state-machine-algebraic-state (feature)

Stories:
- epic-bold-generated-protocol-cockpit-control-rpc-step-2
- epic-bold-reachability-contract-pi-adapter-step-1..4
- epic-bold-reachability-contract-state-machine-step-2
- epic-bold-transcript-event-log-hydration-replay-step-3
- epic-bold-transcript-event-log-projection-derive-step-4
- epic-bold-transcript-event-log-store-step-3

### Excluded — to_room sender fix (unbound, deferred to design)

`story-to-room-sender-side-room-targeting` (kept at `stage: drafting`, unbound).

The handoff framed this as a mechanical “thread it through,” but scoping
revealed it is design-bearing: the ACK and data-envelope sites are clean (relay
echoes `to_room`; destination room is derivable from the cached roster via
`roomIdFor(cwd, name)`), but the control-envelope site (`peers_request`/
`peers_update` bootstrap) hits a real chicken-and-egg — the first `peers_request`
that should *warm* the roster cache can't be sent because targeting it requires
already knowing the sibling's room. The bootstrap solution needs a deliberate
design choice (well-known control room joined by every MeshNode; or a
control-only relay fanout; or `room_id` in the out-of-band `mesh_versions`
member). Routing through `refactor-design` (it is the sender half of the
already-`[refactor]`-tagged `relay-opaque-targeting` feature) before implementing.

**This does not block extension-0.6.0:** commit `13701ee` already made the
sender emit `to_room` (with a temporary `"main"` value), so wire-compatibility
with relay-0.2.0 is satisfied — the field is present and the relay accepts it.
The `"main"` default is pre-existing breakage (cross-PC delivery to a real room
non-functional since `13701ee`), not a regression the 18 done items introduce.
None of the 18 touch the `to_room` sender path.

### Excluded archived stubs (2)

Both unbound archived stubs at `.work/archive/` are `status: superseded`
(`superseded_by: epic-bold-split-pi-extension-index-sdk-session-projection-module`,
which is already bound above). They are superseded drafts, not done stubs —
binding them would double-count work already represented by their replacement.
Excluded deliberately; documented here so the gather is auditable.

- story-fix-cross-pc-bridge-late-attach-after-shutdown (superseded)
- story-investigate-model-thinking-actions-after-session-replacement (superseded)

## Gate runs

- **gate-docs** (2026-07-01) — 2 findings (2 medium). Grep-first prompt held (1
  compaction, recovered). Both routed to backlog (non-blocking):
  - `gate-docs-composition-root-session-hooks` (medium) — pi-extension-typescript
    SKILL.md lifecycle docs reference the old monolithic `index.ts` session hooks;
    now split across `src/extension/composition_root.ts`.
  - `gate-docs-peer-join-broadcast-location` (medium) — SKILL.md describes
    `peer_joined`/`peer_left` broadcast location pre-split.
- **gate-cruft** (2026-07-01) — 4 findings (1 high blocking, 3 medium). Tightly
  scoped to split-module files; no compaction. The high finding **resolved**:
  - `gate-cruft-unused-command-surface-legacy-deps` (high → resolved): orphaned
    incremental-split seam `src/extension/command_surface/legacy_deps.ts` —
    deleted; the live `LegacyCommandSurfaceDeps` interface lives in
    `legacy_ports.ts`. Typecheck + extension tests green.
  - 3 medium → backlog (non-blocking): relay-owner-channel-bridge,
    standalone-cli-unused-command-surface, index-legacy-test-aliases.

- **gate-refactor** (2026-07-01) — 8 findings (4 high, 4 medium, 0 low) from 3 libraries: protocol-contract (4 findings), lifecycle (4 findings), boundaries (0 findings). High findings routed to blocking active stories; medium findings routed to backlog per `gate_finding_routing`. Ran inline because this sub-agent had no nested scanner dispatch tool; scan stayed grep-first and bundle-scoped.
  - High/blocking: `gate-refactor-protocol-relay-client-control-dtos`, `gate-refactor-protocol-pi-forward-crosspc-dtos`, `gate-refactor-protocol-room-meta-literal`, `gate-refactor-lifecycle-relay-auth-timeout-listener`.
  - Medium/backlog: `gate-refactor-protocol-session-scope-reenumeration`, `gate-refactor-lifecycle-session-start-fire-and-forget`, `gate-refactor-lifecycle-queued-delivery-fire-and-forget`, `gate-refactor-lifecycle-control-frame-fire-and-forget`.

(populated in Phase 4 — remaining gates pending)

## Wire-change deployment note

Carried from relay-0.2.0: the `to_room` field is now required on cross-PC
`pi_envelope` frames. The extension-0.6.0 sender (per commit `13701ee`, already
in tree before this release) emits `to_room` with a temporary `"main"` value —
so the wire shape is compatible with relay-0.2.0 (field present, relay accepts
it). The remaining sender-side work — targeting the sibling's *actual* room
instead of the `"main"` placeholder — is deferred to design (see Excluded
section above); it does not change the wire contract, only which room value the
sender writes.

### Binding-consistency warnings

BINDING CONSISTENCY — release extension-0.6.0 (epic_cohesion: phased):
  • 0 CONFLICTs.
  • 34 INCOMPLETEs — all `[refactor]`-tagged step-children of the 7 bound
    pi-extension features, routing to repo-level v0.6.0 per the attribution
    rule (no component tag → repo-level). [informational under epic_cohesion: phased]

Established fork pattern (matches cockpit-v1.6.0 / app-v1.2.0 / relay-0.2.0):
bold-refactor *steps* carry only `[refactor]` and ship in the repo-level
release; the *parent features/stories* carrying the `[pi-extension]` tag bind
to the component release. Verified the 25 `split-pi-extension-index-*` and
`turn-state-machine-algebraic-state` step commits touch only `pi-extension/`
(genuinely pi-extension code, but deliberately repo-level-tagged per
convention). The 5 `generated-protocol-ts-codegen` steps touch shared
`tools/` + `protocol/` codegen infra → legitimately repo-level.

One data-integrity flag for v0.6.0 (not blocking here):
`turn-state-machine-algebraic-state-step-3` is stage:done but has no
`implement:` commit — investigate when picking up v0.6.0.
