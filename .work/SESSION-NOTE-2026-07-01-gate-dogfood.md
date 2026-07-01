# Session note — 2026-07-01 — gate dogfood releases (cockpit/app/relay)

Transient handoff note. Per `.agents/rules/agent-discipline.md` this lives in
`.work/` (transient) and is NOT a durable artifact. Delete when the work it
describes is fully resolved; do not link durable docs at it.

## What happened this session

Continued from the prior session's bold-refactor drain + scan-library authoring.
This session: activated the refactor gate, then ran **3 component releases**
through the full gate-enabled release pipeline as a dogfood, plus implemented
two real correctness/security fixes the gates surfaced.

### Gate setup (already committed prior)
- `gates_for_release: [security, tests, cruft, docs, patterns, refactor]` (6 gates).
- 3 scan libraries under `.agents/skills/scan-{boundaries,lifecycle,protocol-contract}/`,
  all `findings-route: none` (untagged — fixes aren't black-box-preserving).
- **Encoded durable policy**: `gate_finding_routing: { critical: implementing, high: implementing, medium: backlog, low: backlog }` — critical/high block the release; medium/low route to `.work/backlog/` as non-blocking tracked work. An operator may case-by-case keep a medium/low finding blocking (e.g. debug artifact in production).

### Releases shipped (3)

| Release | Items | Blocking findings resolved | Tag |
|---|---|---|---|
| cockpit-v1.6.0 | 12 | 5 (2 crit tests, 2 high docs, 1 med cruft temp-trace) | pushed ✓ |
| app-v1.2.0 | 14 | 2 high (signing-oracle + dispose-leak) | pushed ✓ |
| relay-0.2.0 | 32 | 5 critical (to_room routing) | **local, NOT pushed** |

Push: `git push origin main relay-0.2.0` (tag points at `93eff11`).

### The headline fix: `to_room` cross-PC routing (relay-0.2.0)

The tests gate caught that `relay-opaque-targeting-step-1` was **approved claiming**
`to_room` parsing + `bad_envelope`, but `handle_pi_envelope` only checked `to_pc`
and `PiEnvelopeFrame` had no `to_room` field — the feature was never implemented.
Implemented across: schema → codegen (Rust + TS) → relay handler → pi-extension
sender → PROTOCOL.md → 11 tests. Commit `13701ee`.

### Two wire changes requiring PAIRED deployment

1. **Auth domain-separation** (app-v1.2.0 ↔ relay-0.2.0): app signs
   `remote-pi-relay-auth-v1\n` ++ nonce; relay verifies the same. Old app + new
   relay (or vice versa) fails auth.
2. **`to_room` required** (relay-0.2.0 ↔ extension-0.6.0 sender): old pi-extension
   sending `{to_pc, envelope}` without `to_room` → `bad_envelope`.

**Deploy relay together with app + pi-extension.** The pi-extension sender
currently passes `"main"` as a temporary default `to_room` (broker_remote.ts:357,
466, 531) — proper broker room-targeting lands in `extension-0.6.0` (next).

## Gate-machinery observations (for fresh context)

- **Docs gate was compaction-prone** (failed 3× on app, once cockpit) with the
  default prompt on `gpt-5.3-codex-spark`. **Fix that worked**: tighter grep-first
  prompt ("grep for assertions, read only matching lines ±3, NEVER read whole
  files; if you find yourself reading a whole file, STOP and grep"). Held on relay
  (1 low finding, no compaction). Apply this prompt shape for `v0.6.0`.
- **Cruft gate**: scoping to ~10 cruft-prone files + grep-first avoided compaction
  on app + relay (cockpit's first run failed at ~40 files / 2 compactions). For
  `v0.6.0` (large), keep cruft tightly scoped.
- The **scan libraries worked end-to-end**: refactor gate produced real findings
  with zero fabricated file:lines (grounding corrections held); protocol-contract
  correctly returned 0 on clean generated-protocol consumption. The
  `ad-hoc-wire-parse` rule's "no generated type → medium/needs-DTO" branch fired
  correctly on the mesh-members blob at `pi_forward.rs:106`.
- **Binding-consistency guard** surfaces 3-6 CONFLICTS + INCOMPLETES per release
  — all expected phased-delivery artifacts (multi-component parents route to
  repo-level `v0.6.0`). Non-halting under `warn`/`phased`.

## Resume instructions (fresh context)

### Next: `extension-0.6.0` (18 pi-extension items)

1. Load `.agents/skills/pi-extension-typescript/SKILL.md` before editing
   pi-extension code.
2. Gather pi-extension-attributed done items (18) + bind to `extension-0.6.0`.
   Same release-deploy flow: bind → Phase 3.5 guard → 6 gates → resolve
   critical/high → Phase 5.5 changelog → ship (tag `extension-0.6.0`).
3. **Complete the `to_room` sender-side room-targeting**: the broker currently
   passes `"main"` as default `toRoom` (broker_remote.ts:357,466,531). The proper
   fix threads the actual destination room through `broker_remote` →
   `sendEnvelopeToPi`. This is the remaining half of the `to_room` work; it may
   surface as a gate finding or just be done as part of the release.
4. Apply the gate-prompt lessons: docs gate grep-first, cruft scoped.

### Then: `v0.6.0` (111 repo-level items — the big one)

- Cross-cutting bold-refactor work (multi-component epics/features/stories).
- **Tighten cruft + docs gate prompts** for the large bundle (compaction risk).
- This is the largest release; expect the most gate findings.

### Backlog

44 gate-produced backlog items across `.work/backlog/gate-*` (cruft, docs,
security, refactor, tests — all medium/low, non-blocking). Not release-blocking;
drain opportunistically.

### Still-outstanding operator action (carried from prior session)

Fresh app build + sideload for the **Hive re-key** (transcript-event-log-store
path-safety fix touched Hive box keys; existing installs need the re-key).
Independent of gates. The app-v1.2.0 sideload covers this IF the operator
sideloads the new app build.

## Untracked secrets

`.key` / `.pem` in the working tree are local secrets — leave untracked, do NOT commit.
