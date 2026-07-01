# Rule: Resource Not Disposed

> Every long-lived resource (StreamSubscription, Timer, TextEditingController, WebSocket, ViewModel, controller) must be cancelled/disposed/closed on its lifecycle boundary.

## Motivation

Remote Pi's mobile and desktop surfaces hold many long-lived resources: WebSocket subscriptions,
presence/rooms streams, watchdog and ping timers, text/scroll controllers. If the owning class
does not cancel/dispose them on its lifecycle boundary, they leak: the subscription keeps firing
into a dead ViewModel, the timer keeps ticking, the controller holds native resources. The leak
is also a correctness bug — a stale subscription can resurrect cleared state or deliver into an
unmounted widget.

The principle is in [`.agents/rules/code-design.md`](../../../rules/code-design.md) → Lifecycle ownership.

## Signals

A class declares a resource field but has no `dispose()`/`close()`/`cancel()` that tears it down,
or tears it down on only some exit paths:

- `StreamSubscription? _sub;` with no `_sub?.cancel()` in a `dispose()`
- `Timer? _t;` / `Timer.periodic(...)` with no `_t?.cancel()`
- `TextEditingController` / `ScrollController` / `FocusNode` with no `dispose()`
- A WebSocket/broker socket with no `close()` on shutdown
- A `dispose()` that cancels `_subA` but not `_subB`

## Before / After

### From this codebase: many resources, dispose must cover all

**Current — `app/lib/data/sync/sync_service.dart:41-44`:**
```dart
StreamSubscription<ConnectionStatus>? _connSub;
StreamSubscription<ServerMessage>? _msgSub;
StreamSubscription<Map<String, List<RoomInfo>>>? _roomsSub;
StreamSubscription<Map<String, PresenceState>>? _presenceSub;
```
A class holding 4 subscriptions. The rule fires if its `dispose()`/`close()` does not cancel
**all four** — a common defect is cancelling the first two and missing `_roomsSub`/`_presenceSub`
on an error/early path.

**Before (violation):**
```dart
@override
void dispose() {
  _connSub?.cancel();
  _msgSub?.cancel();
  // _roomsSub and _presenceSub leaked — never cancelled
  super.dispose();
}
```

**After:**
```dart
@override
void dispose() {
  _connSub?.cancel();
  _msgSub?.cancel();
  _roomsSub?.cancel();
  _presenceSub?.cancel();
  super.dispose();
}
```

### From this codebase: timers

**Current — `app/lib/data/transport/connection_manager.dart:169, 1185`:**
```dart
_watchdogTimer = Timer.periodic(const Duration(seconds: 15), (_) { ... });
_pingTimer = Timer.periodic(const Duration(seconds: 25), (_) async { ... });
```
Two periodic timers. The rule fires if the owning class's teardown does not `cancel()` both.

## Exceptions

- **Locally-scoped resources** — a `StreamSubscription` declared inside a single function and
  cancelled before that function returns (e.g. `session_read_repository.dart:29` declares a local
  `sub` for a one-shot read) is fine; verify it is cancelled on all local exit paths.
- **Owned by a child** — a controller owned by a child ViewModel that disposes itself is not the
  parent's responsibility; check the child instead.
- **Test fixtures** — may skip disposal for brevity; skip test files.
- **Generated code** — skip.

## Scope

`app/lib/**`, `cockpit/lib/**`, `pi-extension/src/**`, `relay/src/**` — excluding tests and
generated code.
