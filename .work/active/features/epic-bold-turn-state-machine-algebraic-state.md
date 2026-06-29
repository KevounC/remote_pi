---
id: epic-bold-turn-state-machine-algebraic-state
kind: feature
stage: implementing
tags: [refactor, bold, pi-extension]
parent: epic-bold-turn-state-machine
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Turn — algebraic state set (riskiest — design first)

## Brief
The canonical `Turn` states + transition rules. Candidate set: `Idle →
Working(replyTo) → Streaming → Done(awaitingSync) → Idle`. The risk: the turn
has real subtleties — steer (mid-turn redirect), cancel, compaction (manually
brackets working today), and session replacement mid-turn. This feature must
prove a small state set can hold all four edge cases without state explosion
before the projection consumers and late-attach children commit to it.

## Epic context
- Parent epic: `epic-bold-turn-state-machine`
- Position: riskiest child — the state set's feasibility is what the rest of
  the epic hangs on. Design FIRST.

## Foundation references
- Evidence of the unnamed machine: `pi-extension/src/index.ts:538-544`
  (`_currentTurnId`, `_turnActive`, `_finishedTurnIdAwaitingSync`,
  `_queuedMessage`); compaction brackets `index.ts:1524-1537`; turn seed
  `index.ts:3284-3313`; agent end + late-sync `index.ts:1476-1484`,
  `:3324-3337`.

<!-- /agile-workflow:refactor-design pins the state set + transitions,
resolving the edge-case explosion risk. -->

## Refactor Overview

The current turn lifecycle is an implicit state machine split across nullable ids,
booleans, set membership, queued-message state, room metadata patches, and app-side
corrections. The high-value refactor is to make the lifecycle algebraic in one
pure reducer first, then route the pi-extension hooks through that reducer without
changing the existing wire messages. The dependent `projection-consumers` sibling
can then project app/cockpit/relay UI state from the same state machine instead of
re-inferring it from `working`, streaming buffers, and local fallbacks.

### State set and projections

Canonical turn states for this feature:

1. `Idle` — no active turn, no late-attach sync pending; projects `working:false`.
2. `Working(replyTo, source)` — a user/local/queued/compaction turn has been accepted
   or the SDK turn has started, but no current text/tool sub-phase is known yet;
   projects `working:true`.
3. `Streaming(replyTo)` — assistant text deltas are flowing; projects `working:true`.
4. `AwaitingTool(replyTo, toolCallId)` — a tool is running/visible inside the turn
   (not approval-gated); projects `working:true`.
5. `Done(awaitingSync)` — terminal success is known, late-attach/session-sync work may
   still need to flush; projects `working:false`.
6. `Error(reason)` — provider error, cancel/abort, delivery failure, session replacement,
   or shutdown terminal path; projects `working:false`.

`working` is a derived projection, not a primary state. The invariant is:

```text
working == state in { Working, Streaming, AwaitingTool }
working == false for Idle, Done, Error
```

Terminal convergence rule: success, provider error, abort/cancel, compaction,
reconnect/session replacement, and shutdown all transition to `Done` or `Error`
before returning to `Idle`, and therefore all project `working:false` and a null
cancel target. Duplicate `working:false` patches are acceptable and idempotent;
stuck `working:true` is not.

### Transition rules

| Event | Transition |
|---|---|
| `user_message_accepted` / `local_input` | `Idle/Error/Done -> Working(replyTo)`; active steering preserves the existing `replyTo`/turn id. |
| `turn_start` | Keeps an already-seeded app turn id or creates a `local_...` turn id for terminal/RPC turns; clears prior `Done(awaitingSync)`. |
| `agent_chunk` | `Working/AwaitingTool/Streaming -> Streaming`; same `replyTo`. |
| `tool_execution_start` | `Working/Streaming -> AwaitingTool`; same `replyTo`, records `toolCallId`. |
| `tool_execution_end` | `AwaitingTool -> Working` so later text/tool/done events stay in the same turn. |
| `agent_done` | Active states -> `Done(awaitingSync)` and project `working:false`. |
| `turn_end` | Flushes late-attach sync if `Done(awaitingSync)` is ready, then allows queued drain and `Idle`. Idempotent after `agent_done`. |
| `provider_error` / `delivery_error` | Active or seeded state -> `Error(reason)` and project `working:false`. |
| `cancelled` / abort acknowledgement | Active state -> `Error(reason:"cancelled")`; app-visible `cancelled` frame remains unchanged. |
| `compaction_start` / `compaction_done` | Model compaction as a synthetic `Working(source:"compaction") -> Done -> Idle`, not a seventh state. |
| `session_shutdown` / replacement | Any state -> `Error(reason:"session_shutdown") -> Idle`; clears stale turn/cancel/queue ownership. |
| `peer_attached` | Records late-attach targets only while the SDK turn is still collecting them; no effect when idle. |
| `queued_message_set/clear` | Updates the snapshot's queued slot; drain is legal only when projection says `canDrainQueuedMessage`. |

### Location and future migration rationale

The interim source of truth should live in `pi-extension/src/session/turn_state.ts`
as a pure, dependency-free reducer and projection module. It is deliberately shaped
as const registries + inferred unions so the generated-protocol epic can later move
this same state table into schema/profile metadata and generate TypeScript/Dart/Rust
views. This keeps the fork-private refactor useful now without baking in a shape that
blocks patchbay or generated schema migration.

### Scan findings and rationale

- **Code smell: unnamed machine in `pi-extension/src/index.ts`.** `_currentTurnId`,
  `_turnActive`, `_finishedTurnIdAwaitingSync`, `_peersAttachedDuringTurn`, and
  `_queuedMessage` jointly encode one lifecycle with no transition table.
- **Missing abstraction: `working` as parallel truth.** `turn_start/turn_end`,
  compaction hooks, app `SyncService._setWorking`, and `ConnectionManager.markRoomWorking`
  all correct the same lifecycle after different observations.
- **Pattern drift: metadata typing drift.** `pi-extension/src/transport/relay_client.ts`
  still types `RoomMeta`/`RoomMetaUpdateFrame` as model-only while runtime code also sends
  `thinking` and `working`.
- **Not worth doing here:** app/cockpit UI projection rewrites are intentionally deferred
  to `epic-bold-turn-state-machine-projection-consumers`; this feature defines and proves
  the state machine they will consume.

### Coordination / cycle check

Frontmatter cycle check by direct grep: this feature has `depends_on: []`; the
projection-consumers and late-attach sibling features depend on this feature; no
active item currently depends on any of the new step stories. The child stories
therefore form a linear acyclic chain:

`step-1 -> step-2 -> step-3`.

## Refactor Steps

### Step 1: Define the canonical Turn algebra and reducer

**Priority**: High  
**Risk**: Medium  
**Source Lens**: missing abstraction / code smell  
**Files**: `pi-extension/src/session/turn_state.ts`, `pi-extension/src/session/turn_state.test.ts`  
**Story**: `epic-bold-turn-state-machine-algebraic-state-step-1`

**Current State**:
```ts
// pi-extension/src/index.ts
let _currentTurnId: string | null = null;
let _turnActive = false;
let _finishedTurnIdAwaitingSync: string | null = null;
const _peersAttachedDuringTurn = new Set<string>();

type QueuedMessage = { id: string; text: string };
let _queuedMessage: QueuedMessage | null = null;
```

**Target State**:
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
export function projectTurn(snapshot: TurnSnapshot): TurnProjection;
```

**Implementation Notes**:
- Keep the reducer pure and deterministic: no Pi SDK, relay, timers, UUID generation,
  filesystem, or logging imports.
- Accept generated ids as event payloads so test fixtures cover local/RPC turns without
  random output.
- Export selectors/projections instead of letting consumers inspect raw internals.
- Treat compaction as a synthetic turn and cancel/session replacement as terminal `Error`
  reasons, not extra top-level states.

**Acceptance Criteria**:
- [ ] `corepack pnpm test -- turn_state` (or nearest Vitest filter) passes from `pi-extension/`.
- [ ] Reducer tests cover normal app turn, local/RPC turn, steering, tool boundary,
  provider error, cancel, compaction, late attach, queued drain, and session shutdown.
- [ ] `projectTurn(...).working` is false for `idle`, `done`, and `error`, and true only
  for `working`, `awaiting_tool`, and `streaming`.
- [ ] No runtime behavior changes yet; this step only adds the algebra and tests.

**Rollback**: Delete the new `turn_state.ts` and `turn_state.test.ts` files.

---

### Step 2: Replace pi-extension turn booleans with the reducer

**Priority**: High  
**Risk**: High  
**Source Lens**: code smell / missing abstraction  
**Files**: `pi-extension/src/index.ts`, `pi-extension/src/session/turn_state.ts`,
`pi-extension/src/transport/relay_client.ts`, `pi-extension/src/extension.test.ts`  
**Story**: `epic-bold-turn-state-machine-algebraic-state-step-2`

**Current State**:
```ts
pi.on("agent_end", () => {
  if (!_currentTurnId) return;
  const finishedTurnId = _currentTurnId;
  if (_anyPeerActive()) {
    _broadcastToActive({ type: "agent_done", in_reply_to: finishedTurnId });
  }
  _currentTurnId = null;
  _finishedTurnIdAwaitingSync = finishedTurnId;
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});

pi.on("turn_start", (_event, ctx) => {
  _turnActive = true;
  _finishedTurnIdAwaitingSync = null;
  _peersAttachedDuringTurn.clear();
  if (_currentTurnId === null) _currentTurnId = `local_${randomUUID()}`;
  _publishWorking(true);
});

pi.on("turn_end", () => {
  _turnActive = false;
  _publishWorking(false);
  _maybeSendLateAttachSessionSync();
  _maybeDrainQueuedMessage();
});
```

**Target State**:
```ts
let _turn = initialTurnSnapshot();

function _applyTurn(event: TurnEvent): TurnProjection {
  const before = projectTurn(_turn);
  _turn = reduceTurn(_turn, event);
  const after = projectTurn(_turn);
  if (before.working !== after.working) _publishWorking(after.working);
  return after;
}

pi.on("turn_start", (_event, ctx) => {
  _applyTurn({ type: "turn_start", fallbackTurnId: `local_${randomUUID()}` });
  _hydrateModelIfNeeded(ctx);
});
```

`relay_client.ts` metadata types should match the live metadata surface:

```ts
export interface RoomMeta {
  name: string;
  cwd: string;
  model?: string;
  thinking?: ThinkingLevel;
  working?: boolean;
}
export interface RoomMetaUpdateFrame {
  type: "room_meta_update";
  room_id: string;
  meta: { model?: string; thinking?: ThinkingLevel; working?: boolean };
}
```

**Implementation Notes**:
- Preserve existing wire behavior and message names; this is an internal state refactor.
- Centralize working publication through the projection. Duplicate `working:false` is okay;
  stuck `true` is not.
- Preserve steering semantics: steering must not replace the active reply target, while a
  reconnecting app with no current id may seed a fallback id just as today.
- Preserve late-attach semantics: peers attached during an SDK turn get final history after
  terminal state is safe to flush.
- Preserve queue semantics: queued prompts drain only after terminal/idle projection allows it.

**Acceptance Criteria**:
- [ ] `corepack pnpm typecheck` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` (or nearest Vitest filter) passes from `pi-extension/`.
- [ ] Existing tests for working true/false, compaction, late owner attach, steering,
  and queued messages still pass.
- [ ] `index.ts` has no module-level `_currentTurnId`, `_turnActive`,
  `_finishedTurnIdAwaitingSync`, `_peersAttachedDuringTurn`, or `_queuedMessage` globals.
- [ ] `RoomMeta`/`RoomMetaUpdateFrame` TypeScript types include `thinking` and `working`.

**Rollback**: Revert `index.ts`, `relay_client.ts`, and related tests to the previous
boolean-based implementation. Step 1 can remain unused if this integration is backed out.

---

### Step 3: Prove terminal convergence and document the projection handoff in code

**Priority**: High  
**Risk**: Medium  
**Source Lens**: testing-integrity convergence requirement / pattern drift  
**Files**: `pi-extension/src/extension.test.ts`, `pi-extension/src/session/turn_state.test.ts`,
`pi-extension/src/session/turn_state.ts`, optional `pi-extension/src/session/turn_projection.ts`  
**Story**: `epic-bold-turn-state-machine-algebraic-state-step-3`

**Current State**:
```ts
// Tests assert individual symptoms rather than one invariant across all terminal causes.
expect(updates[0]!.meta?.working).toBe(false);
expect(_getCurrentTurnIdForTest()).toBe(null);
```

**Target State**:
```ts
const terminalCases: Array<[string, TurnEvent[]]> = [
  ["success", [turnStart("u1"), agentDone(), turnEnd()]],
  ["provider error", [turnStart("u1"), providerError("u1"), turnEnd()]],
  ["abort", [turnStart("u1"), cancelAck("u1"), turnEnd()]],
  ["compaction", [compactionStart("c1"), compactionDone("c1")]],
  ["session replacement", [turnStart("u1"), sessionShutdown()]],
];

for (const [name, events] of terminalCases) {
  test(`${name} converges working=false`, () => {
    const final = events.reduce(reduceTurn, initialTurnSnapshot());
    expect(projectTurn(final).working).toBe(false);
    expect(projectTurn(final).cancelTargetId).toBeNull();
  });
}
```

Code-level projection handoff:

```ts
export interface TurnProjection {
  working: boolean;                 // existing room_meta projection
  activeTurnId: string | null;       // agent_chunk/agent_done/cancel target
  awaitingSyncTurnId: string | null; // late-attach sibling replaces nullable string with this
  canDrainQueuedMessage: boolean;
  phase: TurnState["tag"];
}
```

**Implementation Notes**:
- Add hook/router-level tests where possible, not only reducer tests.
- Keep app/cockpit/relay consumer rewrites out of this story; the projection-consumers sibling
  owns those changes.
- Do not add a new explicit `turn_state` wire message in this refactor. That would be a
  behavior-changing protocol feature and should be separately scoped.

**Acceptance Criteria**:
- [ ] `corepack pnpm test -- turn_state` passes from `pi-extension/`.
- [ ] `corepack pnpm test -- extension` passes from `pi-extension/`.
- [ ] Tests prove `working:false` and null cancel target after success, provider error,
  cancel/abort, compaction, session replacement/shutdown, and reconnect/late attach recovery.
- [ ] `Done(awaitingSync)` remains represented in state/projection; no nullable
  `_finishedTurnIdAwaitingSync` special case remains.
- [ ] Projection handoff is clear in exported types/comments for the dependent siblings.

**Rollback**: Revert the added convergence tests/projection comments. Do not weaken tests;
if they fail, fix the reducer/integration.

## Implementation Order

1. `epic-bold-turn-state-machine-algebraic-state-step-1` — add pure algebra + reducer tests.
2. `epic-bold-turn-state-machine-algebraic-state-step-2` — integrate pi-extension hooks and
   remove scattered turn booleans.
3. `epic-bold-turn-state-machine-algebraic-state-step-3` — prove convergence across terminal
   causes and leave a clear projection handoff for dependent siblings.

## Refactor-design run notes

- Ambiguity resolved by judgment: `AwaitingTool` means “tool running/visible inside the turn,”
  not approval waiting; approval is dormant and not part of current behavior.
- Ambiguity resolved by judgment: compaction does not need a seventh state; it is a synthetic
  `Working -> Done -> Idle` turn so the convergence invariant stays uniform.
- Ambiguity resolved by judgment: app/cockpit/relay consumer rewrites are deferred to the
  dependent projection-consumers feature; this feature must not create new wire behavior.
- Dispatch rationale: no exploratory subagents were used because the refactor target is a bounded
  set of known lifecycle files and the local read-first scan exposed the relevant transition seams.

