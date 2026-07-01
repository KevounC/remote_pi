# Session note — 2026-07-01 — extension-0.6.0 shipped

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when superseded.

## What happened this session

Continued from the prior gate-dogfood session (cockpit/app/relay shipped).
This session: cut **`extension-0.6.0`** through the full 6-gate release
pipeline, plus recovered from a mid-session scope over-reach.

### extension-0.6.0 — SHIPPED (local tag, NOT pushed)

- **22 items** shipped (18 done pi-extension bold-refactor items + 4 gate
  findings resolved/tracked). Tag `extension-0.6.0` → `7219527`.
- **Bundle**: monolithic `src/index.ts` split into `src/extension/*` modules
  (command_surface, composition_root, owner_multiplexer, relay_transport,
  sdk_session_projection); generated TS protocol codegen replaces handwritten
  wire unions; reachability-contract projection; transcript-event-log +
  turn-state-machine projections.
- **6 gates**: docs(2m) · cruft(1h-resolved,3m) · security(2h pre-existing→backlog,11m) · refactor(1h-resolved,3h+4m pre-existing→backlog) · tests(1 crit-resolved,5m) · patterns(3 documented).
- **3 in-scope findings resolved**: orphaned `legacy_deps.ts` seam deleted;
  cross-PC frame DTOs consume generated `CrossPcFramePiEnvelope*` types;
  stale-context `session_start` test coverage extended (model_set/thinking_set
  after new/resume/fork/reload).
- **5 high + 24 medium/low findings deferred to backlog** — all pre-existing,
  not bundle-introduced (provenance grounded to MVP-era commits / reachability-
  only diffs). Disposition rationale recorded in release summary.
- **Suite green**: 718 passed / 3 skipped.

### Push: `git push origin main extension-0.6.0` (operator action)

## Process lesson — the to_room sender over-reach

The handoff said "complete the to_room sender-side room-targeting." Scoping
revealed it is **design-bearing, not mechanical**: the ACK + data-envelope
sites are clean, but the control-envelope bootstrap site hits a real
chicken-and-egg (the first `peers_request` that warms the roster cache can't
be sent because targeting it requires already knowing the sibling's room).

I created a story and jumped straight to implementation, then realized my
cold-cache-drop choice deadlocks bootstrap (`_bootstrapWithSiblings` fires
control at every sibling on construction → all dropped → cache never warms).
Reverted the half-baked `broker_remote.ts`/`pi_forward_client.ts` edits,
unbound the story (kept at `stage: drafting` as design groundwork), and ran
the gates on the 18 done items alone. **The discipline failure (implement
before design) is the lesson — the to_room sender fix needs refactor-design
first to pick the bootstrap solution deliberately.**

### The to_room sender fix — remaining design work

`story-to-room-sender-side-room-targeting` (`stage: drafting`, unbound) holds
the full analysis. Three viable bootstrap solutions (none free):
1. **Well-known control room** every MeshNode joins alongside its leader room
   (relay already supports multi-room per peer; cleanest, ~MeshNode lifecycle
   + second-relay-join change).
2. **Control-only relay peer-wide fanout** (re-opens a sliver of the "no
   fanout" invariant relay-0.2.0 closed; needs a relay deploy).
3. **`room_id` in the out-of-band `mesh_versions` member blob** (no
   chicken-and-egg; cross-component wire change touching app pairing + relay
   mesh store + verify).

**Route through `refactor-design`** — it's the sender half of the already-
`[refactor]`-tagged `relay-opaque-targeting` feature. Do NOT implement inline.

### Does NOT block anything

The `"main"` default is pre-existing breakage (cross-PC delivery to a real
room non-functional since `13701ee`), not a regression any release introduced.
Wire shape is already relay-0.2.0-compatible (sender emits `to_room`; value
is wrong but field is present).

## Next: `v0.6.0` (repo-level — the big one)

- Cross-cutting bold-refactor work: ~110 repo-level items (the `[refactor]`-tagged
  step-children of component features + cross-component epics/features). The
  34 INCOMPLETEs from extension-0.6.0's binding guard are part of this.
- **Tighten cruft + docs gate prompts** for the large bundle (compaction risk).
  The grep-first docs prompt and tightly-scoped cruft prompt held again this
  release — reuse them.
- **Data-integrity flag for v0.6.0**: `turn-state-machine-algebraic-state-step-3`
  is `stage: done` but has no `implement:` commit — investigate when picking up.

## Backlog

Now ~60+ gate-produced backlog items across `.work/backlog/gate-*` (cruft,
docs, security, refactor, tests — all medium/low + 5 high pre-existing crypto/
lifecycle debt). Non-blocking; drain opportunistically. The 5 high ones worth
prioritizing: signing-oracle (extension half of app-v1.2.0's fix),
owner-messages-unsigned, relay-client-control-dtos, room-meta-literal,
relay-auth-timeout-listener.

## Still-outstanding operator action (carried)

1. **Push** `git push origin main extension-0.6.0` (+ `relay-0.2.0` still local).
2. Fresh app build + sideload for the **Hive re-key** (transcript-event-log-store
   path-safety fix; covered IF operator sideloads app-v1.2.0).

## Untracked secrets

`.key` / `.pem` in the working tree are local secrets — leave untracked.
`relay/src/auth/auth_test.rs` has a pre-existing working-tree mod (not mine).
