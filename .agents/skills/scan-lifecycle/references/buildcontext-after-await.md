# Rule: BuildContext After Await

> Flutter `BuildContext` must not be used after an `await` without a `mounted` guard in the same scope.

## Motivation

After an `await`, the widget may have been unmounted (the user navigated away, the build was
replaced). Using `BuildContext` — calling `Navigator.of(context)`, `ScaffoldMessenger.of(context)`,
`context.read()`, `showDialog(context: context)`, or reading a Provider — after `await` without
checking `mounted` can throw or operate on a dead element. This is a top defect class for Flutter
apps in general and is called out in [`.agents/rules/code-design.md`](../../../rules/code-design.md)
→ Lifecycle ownership.

## Signals

In a `State`/`StatelessWidget`/widget method (not a non-widget async function):
```dart
await something();          // yield point — widget may unmount
Navigator.of(context)...;    // context used without a mounted check → violation
ScaffoldMessenger.of(context).showSnackBar(...);
context.read<Foo>().doThing();
showDialog(context: context, ...);
```

The rule fires when `context` (or a variable holding it) is referenced after an `await` in the
same scope with no `mounted` check between the await and the use. A valid guard is either
`if (mounted)` / `if (!mounted) return;` (in a `State`) or `if (context.mounted)` /
`if (!context.mounted) return;` (for a `StatelessWidget`, a helper function receiving a
`BuildContext`, or any site without a `State.mounted` field). `context.mounted` is the Flutter
3.7+ API and is the correct guard in helper functions and `StatelessWidget` build callbacks
where `State.mounted` is unavailable.

## Before / After

### From this codebase: the correct pattern (keep this)

The repo already uses `mounted` guards — `app/lib/ui/pairing/pairing_page.dart`,
`home_page.dart`, `onboarding_page.dart`, `settings_page.dart` all reference `mounted`. The rule
guards against new code that forgets it.

**Correct:**
```dart
await transport.send(...);
if (!mounted) return;
Navigator.of(context).push(...);   // guarded
```

### Synthetic: violation

**Before (violation):**
```dart
Future<void> submit() async {
  final result = await api.request();
  ScaffoldMessenger.of(context).showSnackBar(   // context after await, no guard
    SnackBar(content: Text(result.message)),
  );
}
```

**After:**
```dart
Future<void> submit() async {
  final result = await api.request();
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(result.message)),
  );
}
```

## Exceptions

- **`context` captured into a local before the await** and the local is used after — still a
  violation (the captured reference is just as stale). The guard is required regardless.
- **Non-widget async functions** — a repository/use-case that takes no `BuildContext` is not
  subject to this rule (it has no context to go stale). Only widget-layer code applies.
- **`BuildContext` passed as a parameter to a non-widget function and used after an await there**
  is a violation too (same staleness); flag it.
- **Test code** — skip test files.
- **The await yields to a synchronous-completing future** (`SynchronousFuture`, microtask with
  no real yield) — still flag; the guard is cheap and the scanner cannot prove no yield.

## Scope

`app/lib/ui/**`, `cockpit/lib/**` widget layers — excluding tests. Does NOT apply to non-widget
domain/data code (`app/lib/domain/**`, `app/lib/data/**` have no `BuildContext`).
