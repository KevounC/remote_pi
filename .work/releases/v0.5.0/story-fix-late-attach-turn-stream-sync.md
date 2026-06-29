---
id: story-fix-late-attach-turn-stream-sync
kind: story
stage: done
tags: [pi-extension, app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: v0.5.0
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Fix late attach during active turn missing reply stream

Adversarial review found that when a local/RPC/daemon turn starts while no mobile owner is attached, `_currentTurnId` can remain null. A phone attaching mid-turn can see `working:true` but miss later chunks/done because `pi-extension/src/index.ts` drops assistant deltas and `agent_done` when `_currentTurnId` is null.

## Scope

- Ensure an active turn has a stable reply id even if no owner was attached at turn start.
- Ensure late-attaching owners receive either live chunks/done or an immediate authoritative `session_sync` after the turn completes.
- Preserve normal attached-turn behavior and steering semantics.

## Acceptance Criteria

- [x] Add a pi-extension regression for a local/RPC/daemon turn that starts with no owners, then an owner attaches before completion.
- [x] The attaching owner sees the final assistant reply without requiring a second manual reconnect/sync.
- [x] `working` still converges false on turn end.

## Implementation notes

- Ensured local/RPC turns get a stable `local_...` reply id even when no owner is attached at turn start.
- Preserved active turn ids across owner/relay detach while a turn is active, and tracked owners attaching mid-turn.
- Sent late-attaching owners an authoritative `session_history` after the turn completes, in addition to live chunks/done when they are attached before completion.
- Added a deterministic pi-extension regression in `pi-extension/src/extension.test.ts` for no-owner turn start → owner attach → chunk/done/history + `working:false`.

Verification from `pi-extension/`:

- `corepack pnpm typecheck` — passed.
- `corepack pnpm test -- src/extension.test.ts` — passed; Vitest executed the full 33-file suite (586 passed, 3 skipped).
- `corepack pnpm test` — passed (33 files, 586 passed, 3 skipped).

## Review (2026-06-28)

Verdict: Approve

Findings: None.
