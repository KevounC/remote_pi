---
source_handle: remote-pi-cockpit-bootstrap-modules
fetched: 2026-06-28
source_path: cockpit/lib/main.dart
provenance: source-direct
---

# Remote Pi cockpit bootstrap/modules attestation

## Source summary

Cockpit initializes Flutter bindings, media, orphan-process cleanup, Hive, settings, window state, Pi spawn config, and a `flutter_modular` app module before rendering `ModularApp` and `ShadcnApp.router`. Feature modules own their binds/routes; the cockpit feature module opens its own Hive boxes and provides page-scoped ViewModels.

## Key passages

> `main()` calls `WidgetsFlutterBinding.ensureInitialized()`, `MediaKit.ensureInitialized()`, `PiProcessRegistry.cleanOrphans()`, `LspProcessRegistry.cleanOrphans()`, `Hive.initFlutter(hiveSubdir)`, opens settings/window boxes, runs `_setupWindow`, resolves `PiSpawnConfig`, builds the app module, then runs `ModularApp`.

> `_setupWindow` uses `windowManager.ensureInitialized()`, restores width/height from Hive, sets hidden title-bar window options, and calls `windowManager.waitUntilReadyToShow` with `show()` and `focus()`.

> `_WindowStateKeeper` implements `WindowListener`, registers with `windowManager.addListener`, persists window size on resize with a debounce, removes the listener, and cancels the timer on dispose.

> `AppRoot` renders `ShadcnApp.router` and reads `SettingsController` via `context.watch<SettingsController>()`; it wraps the router child with app-level shortcut handling, zoom, and Cockpit theme tokens.

> `buildAppModule` composes `core`, `cockpit`, and `settings`; comments state the root module is only composition and that submodules declare their own paths.

> `buildCockpitModule` returns `createModule(path: '/', register: ...)`, registers data adapters and repositories, and provides `CockpitViewModel`, `SetupViewModel`, and `UpdateViewModel` via `addChangeNotifier(... .new)` on the `/` route.

## Notes for Remote Pi

The module/build lifecycle is the cockpit's composition root. New async resources should be opened in `main` or the owning module builder, then captured in binds; route pages should not instantiate ViewModels or own infrastructure directly.
