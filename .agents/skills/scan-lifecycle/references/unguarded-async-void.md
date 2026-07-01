# Rule: Unguarded Async Fire-and-Forget

> An `async` function whose returned `Future`/`Promise` is never awaited, returned, or explicitly voided swallows errors and breaks lifecycle ordering.

## Motivation

In Dart, calling an `async` function without `await` creates an unawaited Future: errors are
silently dropped (no stack trace surfaces), and the work races with the caller's lifecycle — the
caller may `dispose()` while the fire-and-forget work is still running, producing
use-after-dispose or BuildContext-after-await bugs. In TypeScript the equivalent is a floating
`Promise`. Remote Pi's `.agents/rules/code-design.md` and `testing-integrity.md` both treat
lifecycle/state convergence as the highest-risk class; unguarded fire-and-forget is a root cause.

## Signals

- Dart: a call to an `async` function whose result is not assigned, awaited, or wrapped in
  `unawaited(...)`, especially in a non-`async` callback (button `onPressed`, `initState` body,
  stream listener).
- TypeScript: a call returning `Promise<void>`/`Promise<T>` whose result is discarded, in a
  context that is not itself async and `await`ing.
- Especially: fire-and-forget inside `dispose()` (work racing teardown) or inside a
  `StreamSubscription` callback (work racing the subscription's cancellation).

## Before / After

### Synthetic: violation

**Before (violation) — Dart:**
```dart
@override
void initState() {
  super.initState();
  _loadInitialData();        // async, returns Future — not awaited, not unawaited()
}
```

**After (option A — explicitly unawaited, errors handled internally):**
```dart
@override
void initState() {
  super.initState();
  unawaited(_loadInitialData());   // signals fire-and-forget intent; _loadInitialData must
                                   // try/catch+log internally so errors don't vanish
}
```
**After (option B — await it, if order matters):**
```dart
@override
void initState() {
  super.initState();
  _loadInitialData();   // acceptable only if the function self-handles errors AND
                        // races safely with the widget lifecycle (no context use after await
                        // without a mounted guard — see buildcontext-after-await)
}
```
The fix depends on intent: if the work must complete before continuing, `await` it (and make the
caller async); if it genuinely races safely, wrap with `unawaited(...)` to signal intent and
ensure the async function itself catches and logs all errors so they don't vanish. A bare
`_loadInitialData();` with no `unawaited(...)` and no internal error handling is still a
violation — the "After" must add at least one of those.

### Synthetic: violation — TypeScript

**Before:**
```ts
function onMessage(frame: Frame) {
  handleAsync(frame);        // returns Promise<void>, not awaited — errors vanish
}
```

**After:**
```ts
function onMessage(frame: Frame) {
  void handleAsync(frame).catch(err => log.error({ err }, "handleAsync failed"));
}
```

## Exceptions

- **`unawaited(...)` / explicit `void`** — a call wrapped in `unawaited()` (Dart) or
  `void ... .catch(...)` (TS) signals intent and handles errors; not a violation.
- **Top-level `main()` / event-loop entry** — fire-and-forget at the true entry point is expected.
- **Fire-and-forget with internal try/catch that logs** — if the async function itself catches
  and logs all errors, the error-swallowing concern is addressed; the lifecycle-racing concern
  remains — mark medium confidence.
- **Test code** — skip.

## Scope

`app/lib/**`, `cockpit/lib/**`, `pi-extension/src/**`, `relay/src/**` — excluding tests and
generated code. Does not apply to `site/`.
