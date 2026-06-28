---
source_handle: flutter-modular-7-1
fetched: 2026-06-28
source_url: https://pub.dev/api/archives/flutter_modular-7.1.0.tar.gz
provenance: source-direct
---

# flutter_modular 7.1.0 attestation

## Source summary

The fetched `flutter_modular` 7.1.0 source defines functional modules with `createModule`, optional `path` for feature-scoped binds, route declarations with optional `provide`, an active injector for `inject<T>()`, root-owned pathless modules, and lazy feature bind lifecycle. It also defines page-scoped state registration via `Scoped` with `addChangeNotifier`, `addListenable`, `addStreamable`, `addStream`, and `add`.

## Key passages

> `createModule({ String? path, required void Function(ModularContext c) register })` creates a functional module; the source comments say to give a path to make it a feature and omit it for a shared DI module.

> `Module.path`: a module with a path is a feature whose routes are flattened under the path and whose binds are disposed when its last route leaves; a module without a path is shared DI, root-owned, and never disposed.

> `ModularContext` exposes `route`, `module`, `add`, `addSingleton`, `addLazySingleton`, and `addInstance`.

> `bootstrapModule` walks a root module, commits root binds eagerly, and records feature binds to be bound lazily on entry and disposed on exit.

> `Scoped` is the registrar for page-scoped state used in `route(provide: ...)`; `addChangeNotifier` registers a `ChangeNotifier` view model in a page-local injector and disposes it on unmount.

> `context.watch`, `context.select`, and `context.read` are provided through scoped state, with errors when no scoped value is provided.

## Notes for Remote Pi

Cockpit's local guidance matches the package source: pathless `core` is root-owned; pathful features own their binds; `provide` is the correct place for route/page ViewModels. Constructor tear-offs are preferred locally so auto-injector can resolve parameters from the graph.
