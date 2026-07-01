---
id: release-extension-0.6.0
kind: release
stage: released
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

- **gate-refactor** (2026-07-01) — 8 findings (4 high, 4 medium) from 3 scan libraries
  (protocol-contract 4, lifecycle 4, boundaries 0). 1 high **resolved in-scope**;
  3 high + 4 medium **deferred to backlog as pre-existing** (not bundle-introduced):
  - `gate-refactor-protocol-pi-forward-crosspc-dtos` (high → **resolved**): the `to_room`
    commit (`13701ee`, this bundle) hand-edited the `PiEnvelopeFrame`/`PiEnvelopeInFrame`
    mirror instead of consuming the generated `CrossPcFramePiEnvelope*` types.
    Replaced the handwritten interfaces with the generated types; typecheck +
    76 transport/broker tests green.
  - `gate-refactor-protocol-relay-client-control-dtos` (high → backlog): handwritten
    `HelloMsg`/`AuthMsg`/etc. pre-date `extension-0.5.4` (MVP commit `0956a74`);
    this bundle's `relay_client.ts` diff = reachability constants only.
  - `gate-refactor-protocol-room-meta-literal` (high → backlog): the `room_meta_update`
    literal pre-existed in `index.ts` (already present at `0.5.4`); the split *moved*
    it into `relay_transport.ts` without introducing the handwritten discriminator.
  - `gate-refactor-lifecycle-relay-auth-timeout-listener` (high → backlog): the
    auth-timeout path at `relay_client.ts:253` was last touched MVP-era; bundle
    didn't touch it (reachability-constants-only diff).
  - 4 medium → backlog (non-blocking): session-scope-reenumeration,
    session-start/queued-delivery/control-frame fire-and-forget.
- **gate-security** (2026-07-01) — 13 findings (2 high, 11 medium/low). All routed
  to backlog. The 2 high findings are **pre-existing crypto posture, not bundle
  regressions** — disposition rationale:
  - `gate-security-extension-relay-auth-signing-oracle` (high → backlog): bare-nonce
    signing at `relay_client.ts:238` last touched at MVP commit `0956a74`, not this
    bundle (this release's `relay_client.ts` diff = reachability constants only).
    The app half of this exact finding already shipped fixed in app-v1.2.0
    (`remote-pi-relay-auth-v1\n` prefix); the extension half is the residual
    pair-mate — a cross-component change needing a paired relay+extension deploy.
  - `gate-security-relay-owner-messages-unsigned` (high → backlog): base64-only `ct`
    at `peer_channel.ts:67` introduced at MVP, a deliberate documented rollback;
    this bundle's `peer_channel.ts` diff *adds* lifecycle guards + typed
    `decodeClient` validation (improvements), not the no-MAC posture.
  Gating them here would block a structural-refactor release for unrelated
  long-standing crypto-design debt the bundle didn't touch.
- **gate-tests** (2026-07-01) — 6 findings (1 critical blocking, 5 medium). The
  critical finding **resolved in-scope**:
  - `gate-tests-session-start-model-thinking-actions` (critical → **resolved**):
    missing coverage for `model_set`/`thinking_set` after `session_start`
    replacement reasons `resume`/`fork`/`reload` (acceptance criteria of the
    bound `sdk-session-projection-module`). Extended the existing replacement
    test to assert the fresh `session_start` action API is used and stale `_pi`
    setters are not called across all four reasons. 169 extension tests green.
  - 5 medium → backlog (non-blocking): app-preference-persistence,
    control-command-serialization, daemon-create-flow, localboxes-restart-
    preservation, relay-heartbeat-first-tick.
- **gate-patterns** (2026-07-01) — 3 pattern candidates documented as pattern
  skills under `.agents/skills/patterns/` + `.agents/rules/patterns.md` digest:
  command-surface-adapter-classes, subscription-unsubscribe-contract,
  typed-wire-decoders. No release-blocking findings (pattern gate is non-blocking
  by design).

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

## Shipped items

Bodies live on disk (retain-bodies retention). `git show <git ref>:<former active
path>` recovers any body; under retain-bodies they also remain in
`.work/releases/extension-0.6.0/`.

| id | title | kind | git ref |
|----|-------|------|---------|
| epic-bold-split-pi-extension-index | pi-extension/src/index.ts is four modules pretending to be one file | epic | fc9541c |
| epic-bold-generated-protocol-ts-codegen | Generated protocol — TypeScript codegen target | feature | 7ffe82c |
| epic-bold-reachability-contract-pi-adapter | Reachability — pi-extension relay + mesh adapter | feature | a227eaa |
| epic-bold-split-pi-extension-index-cli-daemon-pairing-module | Split pi-extension index — CLI / daemon / pairing module | feature | defbd09 |
| epic-bold-split-pi-extension-index-composition-root | Split pi-extension index — composition root | feature | 1c03e76 |
| epic-bold-split-pi-extension-index-owner-multiplexer-module | Split pi-extension index — owner multiplexer module | feature | 7394dd4 |
| epic-bold-split-pi-extension-index-relay-transport-module | Split pi-extension index — relay transport module | feature | ebac18e |
| epic-bold-split-pi-extension-index-sdk-session-projection-module | Split pi-extension index — SDK session projection module | feature | fc9541c |
| epic-bold-turn-state-machine-algebraic-state | Turn — algebraic state set | feature | b4d8539 |
| epic-bold-generated-protocol-cockpit-control-rpc-step-2 | Step 2: Parse schema control envelopes in pi-extension input path | story | 7a94ca1 |
| epic-bold-reachability-contract-pi-adapter-step-1 | Step 1: Add pi-extension reachability contract projection module | story | 9ad3558 |
| epic-bold-reachability-contract-pi-adapter-step-2 | Step 2: Consume shared backoff in extension relay reconnect | story | 11007b5 |
| epic-bold-reachability-contract-pi-adapter-step-3 | Step 3: Consume shared backoff in MeshNode relay reconnect | story | 84402d8 |
| epic-bold-reachability-contract-pi-adapter-step-4 | Step 4: Consume shared liveness timings in RelayClient | story | a227eaa |
| epic-bold-reachability-contract-state-machine-step-2 | Step 2: Add the TypeScript Reachability projection module | story | 6f06bd0 |
| epic-bold-transcript-event-log-hydration-replay-step-3 | Step 3: Make session_history replay-compatible | story | c0751a2 |
| epic-bold-transcript-event-log-projection-derive-step-4 | Step 4: Make session history a projection from transcript events | story | 6df733d |
| epic-bold-transcript-event-log-store-step-3 | Step 3: Replace _messageBuffer with TranscriptEventLog | story | 46af73f |
| gate-cruft-unused-command-surface-legacy-deps | Remove unused command-surface legacy deps seam | story | 5f7d388 |
| gate-refactor-protocol-pi-forward-crosspc-dtos | Pi forward client redeclares generated cross-PC frame DTOs | story | c390b55 |
| gate-tests-session-start-model-thinking-actions | Add stale-context model/thinking tests for session_start replacements | story | c390b55 |
| gate-patterns-extension-0.6.0 | Patterns extracted for extension-0.6.0 | story | c390b55 |

## Release metadata

- **Date shipped**: 2026-07-01
- **Mapping**: tag-based (`extension-0.6.0`; push is external — operator runs from their machine)
- **Total items shipped**: 22 (18 done work items + 4 gate findings resolved/tracked)
- **Gate finding totals**: docs 2 (2m) · cruft 4 (1h-resolved, 3m) · security 13 (2h pre-existing→backlog, 11m) · refactor 8 (1h-resolved, 3h+4m pre-existing→backlog) · tests 6 (1 crit-resolved, 5m) · patterns 3 documented
- **Pre-existing findings deferred to backlog**: 5 high (2 security, 3 refactor) + 24 medium/low — all non-bundle-introduced (provenance grounded to MVP-era commits / reachability-only diffs)
- **External publishing**: `git push origin main extension-0.6.0` (tag points at the ship commit)
