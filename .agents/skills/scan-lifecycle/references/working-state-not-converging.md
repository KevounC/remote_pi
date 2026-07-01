# Rule: Working State Not Converging

> The `working` / `isWorking` state must converge to `false` on every exit path: success, error, abort, compaction, reconnect, and shutdown.

## Motivation

When a turn/session shows "working" and never clears it, the UI hangs on a spinner, the cancel
button stays enabled, and the user cannot start a new turn. Remote Pi's bold-refactor
`turn-state-machine` epic made `working` a **derived** getter over a single `AppTurnStatus` enum
so it converges by construction — but any code that keeps an *independent* `working` bool, or
sets it `true` and forgets `false` on one exit path, reintroduces the divergence.

Called out in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Lifecycle ownership
and `.agents/rules/testing-integrity.md` → Async and lifecycle tests (highest-risk class).

## Signals

- A field `bool _working` / `bool working` set to `true` at the start of an operation but with no
  `false` assignment on a visible error/abort/cancel/shutdown path.
- An `isWorking` getter backed by a sticky flag rather than derived from a status enum.
- A `try { working = true; ... } catch` that does not set `working = false` in `finally`.
- A `working = true` with an early `return` before any `working = false`.

**The correct pattern (not a violation):** `working` derived from a single status enum, so it is
`true` iff status is one of the working statuses and `false` otherwise — no separate flag to
forget. `app/lib/domain/session_state.dart:214` shows this:
```dart
bool get working => switch (status) {
  AppTurnStatus.working ||
  AppTurnStatus.awaitingTool ||
  AppTurnStatus.streaming => true,
  AppTurnStatus.idle ||
  AppTurnStatus.done ||
  AppTurnStatus.error ||
  AppTurnStatus.stale => false,
};
```
`app/lib/data/sync/sync_service.dart:129` (`bool get isWorking => turnProjection.working;`)
correctly derives rather than re-storing. Do NOT flag derived getters.

## Before / After

### Synthetic: violation (independent flag, missing error path)

**Before (violation):**
```dart
bool _working = false;
Future<void> runTurn() async {
  _working = true;
  notifyListeners();
  try {
    final r = await api.run();
    _working = false;            // success path clears
    notifyListeners();
  } catch (e) {
    _showError(e);               // error path does NOT clear → spinner hangs
  }
}
```

**After (derive, or cover all paths):**
```dart
// preferred: derive from a status enum like session_state.dart
// or, if keeping a flag: clear in finally
Future<void> runTurn() async {
  _working = true;
  notifyListeners();
  try {
    final r = await api.run();
  } catch (e) {
    _showError(e);
  } finally {
    _working = false;            // all paths clear
    notifyListeners();
  }
}
```

## Exceptions

- **Derived `working` getters** — `bool get working => status == ...` (the `session_state.dart`
  pattern) are the *correct* shape; never flag. The rule targets independent sticky flags.
- **Projection layers** that derive workingness from an event log (the
  `transcript_projection.dart` pattern) are also correct; skip.
- **Abort/cancel that clears via a different code path** — verify the cancel handler sets the
  status/flag false; if it does, no violation even if the run method itself doesn't.
- **Test code** — skip.

## Scope

`app/lib/**`, `cockpit/lib/**`, `pi-extension/src/**`, `relay/src/**` — wherever a working/turn
status lives. Excluding tests and generated code.
