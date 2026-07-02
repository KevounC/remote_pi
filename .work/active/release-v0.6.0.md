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

(populated in Phase 4)

### Binding-consistency warnings

BINDING CONSISTENCY — release v0.6.0 (epic_cohesion: phased):
  • 0 CONFLICTs.
  • 1 INCOMPLETE — `story-to-room-sender-side-room-targeting` (unbound, stage:
    drafting) has parent `epic-bold-canonical-session` bound to v0.6.0.
    [informational under epic_cohesion: phased] — this is the deliberately-
    deferred to_room sender design story (see extension-0.6.0 release notes);
    it is not done, so it does not bind. Legitimate phased delivery.
