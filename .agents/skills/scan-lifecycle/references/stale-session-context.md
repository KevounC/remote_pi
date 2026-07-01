# Rule: Stale Session Context

> Pi SDK `ExtensionContext` captured at one point must not be used after the session has been replaced (`/new`, `/resume`, `/fork`, `/reload`) — re-capture through `session_start` or `withSession` and guard old contexts.

## Motivation

The pi-extension runs inside a Pi session whose context (`ExtensionContext`) is invalidated on
session replacement. A captured context held in a field and read later — across an await, after a
replacement event, or in a callback fired post-replacement — operates on a dead session: writes
go nowhere, reads return stale state, and the extension's view of the session diverges from the
user's. This is called out in [`.agents/rules/code-design.md`](../../../rules/code-design.md) →
Lifecycle ownership as a core invariant.

## Signals

- `ExtensionContext` (or a value derived from one, e.g. `session.ctx`, an emitter, a registered
  command) stored in a **field** (`private eventCtx: ExtensionContext | null`) and read across a
  boundary that may cross session replacement:
  - read after an `await` that could outlive a `/new`/`/resume`/`/fork`/`/reload`
  - read in a timer/callback registered at capture time but fired later
  - read without checking whether the context is still current
- Capturing the context synchronously and using it immediately (no await, no deferred callback) is
  **fine**.

## Before / After

### From this codebase: the binding pattern

**Current — `pi-extension/src/session/sdk_session_projection.ts:126,142`:**
```ts
private eventCtx: ExtensionContext | null = null;

bindSessionContext(ctx: ExtensionContext): void {
  // ...
  this.eventCtx = ctx as unknown as ExtensionContext;
}
```
A context held in a field and bound/re-bound over the session lifecycle. This is the correct
shape *only if every read of `eventCtx` checks currency* — the rule fires when a read path uses
`this.eventCtx` without verifying it is still bound to the live session (e.g. after an await that
crosses a `bindSessionContext` re-bind, or after a `/new` that should have cleared it).

### Synthetic: violation

**Before (violation):**
```ts
async function handleTurn(ctx: ExtensionContext) {
  const result = await someAsyncWork();        // session may /new during this await
  ctx.emit("turn_end", result);                // ctx may be stale — no re-capture or guard
}
```

**After:**
```ts
async function handleTurn(ctx: ExtensionContext) {
  const result = await someAsyncWork();
  if (ctx !== currentSessionContext()) return;  // guard: context replaced
  ctx.emit("turn_end", result);
}
// or: re-capture via withSession(() => ...) / session_start before the post-await use
```

## Exceptions

- **Synchronous capture-and-use** — `ctx` captured and used with no intervening await or deferred
  callback is not stale; skip.
- **`withSession(fn)` / `session_start(fn)` wrappers** — code that always re-captures the live
  context inside the wrapper is the correct pattern; do not flag.
- **Projection/derived fields** — a field that holds a *derived value* (e.g. `sessionStartedAt`)
  rather than the context itself is not a context staleness violation (it may be a
  `working-state-not-converging` concern instead).
- **Test code** — skip.

## Scope

`pi-extension/src/**` (except `*.test.ts`) — this rule is Pi-extension-specific. Does not apply
to `relay/`, `app/`, `cockpit/` (they do not hold `ExtensionContext`), tests, generated code,
`site/`.
