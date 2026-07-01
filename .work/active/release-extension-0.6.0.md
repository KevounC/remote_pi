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

18 active done items (pi-extension-attributed), plus 1 in-flight story for the
`to_room` sender-side room-targeting fix (the remaining half of the relay-0.2.0
`to_room` wire change — see story body).

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

### In-flight story (to_room sender fix)

- story-to-room-sender-side-room-targeting (stage: drafting → implementing → review)

### Excluded archived stubs (2)

Both unbound archived stubs at `.work/archive/` are `status: superseded`
(`superseded_by: epic-bold-split-pi-extension-index-sdk-session-projection-module`,
which is already bound above). They are superseded drafts, not done stubs —
binding them would double-count work already represented by their replacement.
Excluded deliberately; documented here so the gather is auditable.

- story-fix-cross-pc-bridge-late-attach-after-shutdown (superseded)
- story-investigate-model-thinking-actions-after-session-replacement (superseded)

## Gate runs

(populated in Phase 4)

## Wire-change deployment note

Carried from relay-0.2.0: the `to_room` field is now required on cross-PC
`pi_envelope` frames. relay-0.2.0 + the extension-0.6.0 sender must deploy
paired (an old sender omitting `to_room` → `bad_envelope`). This release
completes the sender side by targeting the sibling's actual room instead of
the temporary `"main"` default (commit 13701ee).

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
