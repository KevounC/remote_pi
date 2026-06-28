---
source_handle: provider-package
fetched: 2026-06-28
source_url: https://pub.dev/packages/provider
provenance: source-direct
substrate_confidence: source-direct
---

# Provider package README

Paraphrased summary: `provider` wraps `InheritedWidget` patterns and supplies lifecycle-aware object creation/disposal, lazy loading, DevTools visibility, and common consumption APIs. The README documents `context.watch`, `context.read`, `context.select`, `Consumer`, `Selector`, default vs `.value` constructors, and `MultiProvider`.

## Key passages

- `context.watch<T>()` listens to changes on `T`.
- `context.read<T>()` returns `T` without listening and does not make the widget rebuild; the README notes it cannot be called inside `StatelessWidget.build`/`State.build` but can be called outside those methods.
- `context.select<T, R>(R cb(T value))` listens to a small selected part of `T`.
- Use the default provider constructor to create a new object; do not use `.value` when creating an object.
- Use `.value` when reusing an existing object instance, otherwise the provider may dispose an object still in use.
- `MultiProvider` flattens nested providers without changing behavior.

## Structural metadata

- Source type: package README on pub.dev
- Package observed in repo: `provider: ^6.1.2` in `app/pubspec.yaml`.
