---
id: epic-bold-turn-state-machine-algebraic-state-step-1
kind: story
stage: done
tags: [refactor]
parent: epic-bold-turn-state-machine-algebraic-state
depends_on: []
release_binding: v0.6.0
gate_origin: null
created: 2026-06-29
updated: 2026-07-01
---

# Step 1: Define the canonical Turn algebra and reducer

## Value / lens
- **Priority**: High
- **Risk**: Medium
- **Source Lens**: missing abstraction / code smell

## Files affected
- `pi-extension/src/session/turn_state.ts` (new)
- `pi-extension/src/session/turn_state.test.ts` (new)

## Current State
```ts
// pi-extension/src/index.ts
let _currentTurnId: string | null = null;
let _turnActive = false;
let _finishedTurnIdAwaitingSync: string | null = null;
const _peersAttachedDuringTurn = new Set<string>();

type QueuedMessage = { id: string; text: string };
let _queuedMessage: QueuedMessage | null = null;
```

## Target State
```ts
export const TURN_STATE_TAGS = [
  "idle",
  "working",
  "awaiting_tool",
  "streaming",
  "done",
  "error",
] as const;

export type TurnState =
  | { tag: "idle" }
  | { tag: "working"; turnId: string; replyTo: string; source: TurnSource }
  | { tag: "awaiting_tool"; turnId: string; replyTo: string; toolCallId: string }
  | { tag: "streaming"; turnId: string; replyTo: string }
  | { tag: "done"; turnId: string; awaitingSync: true; collectLateAttach: boolean }
  | { tag: "error"; turnId: string | null; reason: TurnErrorReason };

export interface TurnSnapshot {
  state: TurnState;
  queuedMessage: { id: string; text: string } | null;
  peersAttachedDuringTurn: ReadonlySet<string>;
}

export function reduceTurn(snapshot: TurnSnapshot, event: TurnEvent): TurnSnapshot;
export function projectTurn(snapshot: TurnSnapshot): {
  working: boolean;
  activeTurnId: string | null;
  cancelTargetId: string | null;
  awaitingSyncTurnId: string | null;
  canDrainQueuedMessage: boolean;
};
```

The reducer owns the transition table. It must model these rules without adding new states for each edge case:

| Event | Rule |
|---|---|
| `user_message_accepted` / `local_input` | `Idle/Error/Done -> Working(replyTo)`; steering while active preserves the existing turn id/reply target. |
| `turn_start` | Keeps an already-seeded app turn id or creates a `local_...` id for terminal/RPC turns; clears prior `Done(awaitingSync)`. |
| `agent_chunk` | Active states become `Streaming(turnId)`. |
| `tool_execution_start` | Active states become `AwaitingTool(turnId, toolCallId)`. |
| `tool_execution_end` | `AwaitingTool -> Working` for possible subsequent text/tool events. |
| `agent_done` | Active states become `Done(awaitingSync, collectLateAttach)` and project `working: false`. |
| `turn_end` | Flushes late-attach sync if needed, then allows queued drain and `Idle`. Idempotent after `agent_done`. |
| `provider_error`, `cancelled`, `delivery_error`, `session_shutdown` | Move to `Error` and project `working: false`; shutdown/new-session reset clears queued state. |
| `compaction_start` / `compaction_done` | Compaction is a synthetic turn: `Idle -> Working(source:"compaction") -> Done -> Idle`, not an extra top-level state. |
| `peer_attached` | Records late-attach targets only while the SDK turn is still collecting them; no transition when idle. |

## Implementation Notes
- Keep the module pure: no Pi SDK, relay, timers, random UUID generation, filesystem, or logging imports.
- Accept generated ids as event payloads so tests are deterministic.
- Export selectors/projections instead of exposing raw state internals to consumers.
- Use `as const` registries and inferred unions so later generated-protocol work can migrate this table into schema metadata without changing semantics.

## Acceptance Criteria
- [x] `corepack pnpm test -- turn_state` (or the nearest Vitest filter) passes from `pi-extension/`.
- [x] `reduceTurn` tests cover normal app turn, local/RPC turn, steering, tool boundary, provider error, cancel, compaction, late attach, queued drain, and session shutdown.
- [x] `projectTurn(...).working` is false for `idle`, `done`, and `error`, and true only for `working`, `awaiting_tool`, and `streaming`.
- [x] No runtime behavior is changed yet; this story only adds the canonical algebra and tests.

## Risk
Medium. The risk is choosing a state set that cannot represent existing edge cases. Keep the reducer pure and heavily tested before integration.

## Rollback
Delete the new `turn_state.ts` and `turn_state.test.ts` files. No production call sites should depend on this story alone.

## Implementation Notes
Implemented the pure `pi-extension/src/session/turn_state.ts` reducer/projection module and deterministic Vitest coverage in `pi-extension/src/session/turn_state.test.ts`. The algebra has the six designed states (`idle`, `working`, `awaiting_tool`, `streaming`, `done`, `error`), explicit queued-message and late-attach projections, and keeps all ID generation external via event payloads.

Covered normal app turns, local/RPC fallback turns, steering preserving the active turn id, tool boundaries, provider/delivery/cancel/shutdown terminal convergence, compaction as a synthetic turn, late attach collection, queued drain gating, and session shutdown clearing stale ownership. No production runtime imports this module yet, so behavior is unchanged.

Verification:
- `corepack pnpm vitest run src/session/turn_state.test.ts` — passed (11 tests).
- `corepack pnpm typecheck` — passed.
- `corepack pnpm test -- turn_state` was attempted first, but Vitest treated the extra argument as a broad run and hit pre-existing environment-sensitive daemon/cwd-lock/leader-election/e2e failures plus timeout; the targeted test command above isolates this story's suite.

## Review (2026-06-29)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fast-lane story review with direct commit/file verification (`003e9de`). Confirmed `turn_state.ts` is pure and defines the six-state algebra/reducer/projection without runtime imports, and `turn_state.test.ts` covers the specified app/local/steering/tool/error/cancel/compaction/late-attach/queued/shutdown paths. Ran `corepack pnpm typecheck` successfully and `corepack pnpm vitest run src/session/turn_state.test.ts` successfully (11 tests). A full `corepack pnpm test` attempt timed out after unrelated pre-existing daemon/cwd-lock/leader-election/e2e environment-sensitive failures; the targeted reducer suite passed. Item advanced to `done`.
