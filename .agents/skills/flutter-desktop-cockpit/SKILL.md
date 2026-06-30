---
name: flutter-desktop-cockpit
description: Remote Pi Flutter desktop cockpit reference. Read before editing or reviewing cockpit/ code, Flutter desktop lifecycle, shadcn_flutter UI, flutter_modular modules/routes/binds, Hive persistence, terminal/PTY/file/window/native plugin surfaces, markdown/media rendering, local notifications, or desktop build/test workflows.
updated: 2026-06-28
provenance: skill-reference
---

# Flutter Desktop Cockpit Reference

> Local scope: `cockpit/`
> Versions/context: Dart SDK `^3.11.5`; `shadcn_flutter 0.0.52`; `flutter_modular 7.1.0`; Hive 2.2.x; `xterm` 4.0.0 git override; `kyroon_pty` git override ref `v1.0.5`; native desktop packages include `file_picker`, `window_manager`, `pasteboard`, `desktop_drop`, `flutter_local_notifications`, `media_kit`, `auto_updater`, `ffi`, and `win32`. [remote-pi-cockpit-pubspec]{1}
> Canonical local docs: `cockpit/CLAUDE.md`, `cockpit/lib/app/CLAUDE.md`, `cockpit/lib/app/core/CLAUDE.md`.

## When to load

- Any edit or review under `cockpit/`.
- Any change involving Flutter desktop windows, native plugins, PTY/process lifecycle, terminal rendering/input, file picking/preview/editing, Hive-backed state, local notifications, app update surfaces, or desktop build packaging.
- Any UI work that touches `shadcn_flutter` theme tokens, `flutter_modular` route/bind/provider patterns, or async `BuildContext` usage.

## Commands

Run from `cockpit/`: [remote-pi-cockpit-guidance]{1}

### Sandbox toolchain (dev VM / `codebox`)

The Flutter SDK and pub cache live **in the repo**, not under `/opt` or `/tmp`.
Flutter 3.44.4 (Dart 3.12.2) at `~/projects/remote_pi/.tools/flutter`; pub cache at
`~/projects/remote_pi/.pub-cache` (gitignored). Always set `PUB_CACHE` and call the
binary directly — `flutter` is not on `PATH`, and the default
`/home/agent/.pub-cache` is mounted read-only.

**Cockpit requires `pub get --offline`.** Three deps are git-overridden from
`github.com/jacobaraujo7/*` (`gpt_markdown`, `kyroon_pty`, `xterm`). A global git
config rewrite (`url.git@github.com:.insteadof=https://github.com/`) forces these
HTTPS URLs through SSH, and there is no SSH key in this sandbox, so online clone
fails with `Permission denied (publickey)`. The bare mirrors in
`.pub-cache/git/cache/` resolve cleanly under `--offline`; keep that cache
populated (re-seed from another checkout if it is ever cleared).

```bash
cd cockpit
export PUB_CACHE=~/projects/remote_pi/.pub-cache
~/projects/remote_pi/.tools/flutter/bin/flutter pub get --offline
~/projects/remote_pi/.tools/flutter/bin/flutter analyze
~/projects/remote_pi/.tools/flutter/bin/flutter test
~/projects/remote_pi/.tools/flutter/bin/dart format .
~/projects/remote_pi/.tools/flutter/bin/flutter run -d macos
~/projects/remote_pi/.tools/flutter/bin/flutter build macos
```

Do not commit `build/`, `.dart_tool/`, `macos/Pods/`, generated artifacts, local `.pi/`, logs, or secrets.

## Cockpit responsibility boundary

Cockpit is a desktop operator surface, not the Flutter mobile app. Its local guidance defines it as a macOS-first desktop GUI that spawns and drives local `pi --mode rpc` processes; do not copy `app/` provider/go_router/mobile-reconnect assumptions into this subproject. [remote-pi-cockpit-guidance]{1}

Current architecture is vertical slices under `lib/app/<feature>/{domain,data,ui}` rather than global mobile-style layers. [remote-pi-cockpit-guidance]{1}

```text
ui ──► domain ◄── data
        ▲
 <feature>_module.dart composes binds/routes/ViewModels
```

Rules:

- `domain/` does not import `data/`, `ui/`, Flutter widgets, routes, modules, or native plugins.
- `data/` implements domain contracts and owns IO/process/native-plugin adapters.
- `ui/` consumes domain through page-scoped ViewModels; pages/widgets do not instantiate adapters or ViewModels directly.
- Features may import `core/`; `core/` never imports a feature; features do not import each other.
- Keep `app_module.dart` as composition only; each feature declares its own routes and binds. [remote-pi-cockpit-bootstrap-modules]{1}

## Bootstrap and app lifecycle

`main()` is the cockpit composition root. It initializes Flutter bindings, media, orphan process cleanup, Hive, settings, window state, `PiSpawnConfig`, then builds the Modular app and runs `ModularApp`. [remote-pi-cockpit-bootstrap-modules]{1}

Key lifecycle rules:

- Initialize native/plugin globals before first use: `WidgetsFlutterBinding.ensureInitialized()`, `MediaKit.ensureInitialized()`, `Hive.initFlutter(...)`, and `windowManager.ensureInitialized()` where applicable. [remote-pi-cockpit-bootstrap-modules]{1}
- Open async values such as Hive boxes in `main()` or an async module builder, then inject repositories/stores; do not open boxes from widgets. [remote-pi-cockpit-bootstrap-modules]{1} [hive-2-2-hive-flutter-1-1]{1}
- Window lifecycle is explicit: register `WindowListener`, debounce resize persistence, remove the listener, and cancel timers on dispose. [remote-pi-cockpit-bootstrap-modules]{1}
- Keep orphan-process cleanup paths intact for `pi --mode rpc`, LSP, PTY, and update helpers.

## `flutter_modular` patterns

Cockpit uses `flutter_modular` v7 for DI, routing, and page-scoped state. The package source defines `createModule`, pathful feature modules, pathless root-owned modules, `route(... provide: ...)`, and `Scoped.addChangeNotifier` disposal for page ViewModels. [flutter-modular-7-1]{1}

Pattern:

```dart
Module buildFooModule() => createModule(
  path: '/foo',
  register: (c) => c
    ..addLazySingleton<FooRepository>(FooRepositoryImpl.new)
    ..route(
      '/',
      provide: (s) => s..addChangeNotifier<FooViewModel>(FooViewModel.new),
      child: (context, state) => const FooPage(),
    ),
);
```

Project rules:

- Pathless `core` binds are root-owned; pathful feature binds are feature-scoped. [flutter-modular-7-1]{1}
- Use constructor tear-offs (`Foo.new`) for binds/ViewModels when auto-injector can resolve parameters.
- Use `addInstance` for already-opened boxes, platform-resolved values, or constant adapters.
- Put `init()` / `check()` calls in page `initState`, not chained inside bind factories.
- Prefer named factory interfaces and value objects over raw `Function()` or ambiguous primitive constructor parameters.
- Consume state with `context.watch<T>()`, `context.select<T, R>()`, or `context.read<T>()` from `flutter_modular`'s provider-like API. [flutter-modular-7-1]{1}

## UI and theme (`shadcn_flutter`)

`shadcn_flutter` 0.0.52 is a standalone Flutter UI ecosystem with components, theming, design tokens, optional Material/Cupertino interop, and desktop support. [shadcn-flutter-0-0-52]{1} Cockpit pins it exactly because it is pre-1.0 and API-churn-prone. [remote-pi-cockpit-pubspec]{1}

Rules:

- Root UI is `ShadcnApp.router` under `ModularApp`; the router config comes from `ModularApp.routerConfigOf(context)`. [remote-pi-cockpit-bootstrap-modules]{1}
- Use cockpit theme wrappers (`context.colors`, `context.typo`, `context.syntax`) instead of hardcoded `Color(...)`, package default styles, or ad-hoc fonts.
- `SelectionArea`/Material interop is allowed when a third-party widget needs it, but keep it local and documented. [remote-pi-cockpit-file-media-surface]{1}
- Check the local shadcn pin before copying examples from the online widget catalog or `llms-full.txt`.

## Hive persistence

Hive boxes are the local persistence primitive. Hive exposes `openBox`, `box`, `close`, and box watching; `hive_flutter` adds `initFlutter` and `box.listenable()`. [hive-2-2-hive-flutter-1-1]{1}

Project rules:

- `main()` initializes Hive with a debug/prod subdirectory split; feature builders open their own boxes and inject repositories/stores. [remote-pi-cockpit-bootstrap-modules]{1}
- Do not read/write Hive directly from UI widgets; use repositories/stores and ViewModels.
- Keep box names centralized in the owning store/repository.
- Treat local persistence as user state: avoid destructive migrations without explicit versioning and recovery behavior.

## Desktop native/plugin surfaces

Flutter desktop supports native Windows/macOS/Linux apps and desktop plugins. [flutter-desktop-support]{1} Cockpit relies on native/plugin boundaries for folders/files, window management, notifications, drag/drop, pasteboard, media, update, and Windows IPC. [remote-pi-cockpit-pubspec]{1}

Package checks:

- `file_picker` uses OS native pickers, supports directory picking and save dialogs, but exact platform support varies by API; e.g. combined file+directory picking is macOS-only in current docs. [desktop-native-package-docs]{1}
- `window_manager` controls desktop window size, position, appearance, close behavior, and events; quick start requires binding/window-manager initialization and `waitUntilReadyToShow`. [desktop-native-package-docs]{1}
- `flutter_local_notifications` supports macOS/Linux/Windows, but platform caveats differ: Linux capabilities depend on the notification server, Windows has package-identity limitations, and macOS behavior differs for some launch/scheduling APIs. [desktop-native-package-docs]{1}

Rules:

- Check `pubspec.lock` before using latest package examples: several native packages are behind latest, and some are git overrides. [remote-pi-cockpit-pubspec]{1}
- Add or preserve platform smoke notes when touching PTY, file picker, drag/drop, pasteboard, notifications, window manager, media, update, named pipes, or FFI.
- Do not make a macOS-only behavior look cross-platform unless the package docs and local code prove it.

## Terminal / PTY surface

The terminal is a high-risk lifecycle boundary: `kyroon_pty` spawns a native PTY; `xterm` renders and handles terminal input; Cockpit wraps both behind domain contracts and a custom renderer. [kyroon-pty-1-0-4]{1} [xterm-4-0-0]{1} [remote-pi-cockpit-terminal-surface]{1}

Rules:

- Keep PTY operations behind `TerminalGateway` / `TerminalGatewayFactory`; UI should not call `Pty.start` directly.
- Preserve environment propagation: Cockpit explicitly passes `Platform.environment`, `TERM=xterm-256color`, and `COLORTERM=truecolor`. [remote-pi-cockpit-terminal-surface]{1}
- Decode output as a stream with malformed UTF-8 tolerance before writing to `Terminal`; do not assume chunk boundaries align with characters. [remote-pi-cockpit-terminal-surface]{1}
- Bound scrollback (`Terminal(maxLines: ...)`) and avoid unbounded log/string accumulation.
- Forward resize from xterm width/height to PTY rows/columns.
- On dispose: cancel output subscription, kill the PTY, and dispose UI/focus/listener resources. [remote-pi-cockpit-terminal-surface]{1}
- Private xterm imports in `cockpit_terminal.dart` are a contained exception for swapping the render object; do not spread `implementation_imports` elsewhere. [remote-pi-cockpit-terminal-surface]{1}

## File, markdown, code, and media surfaces

`FileViewer` handles markdown, text/code, SVG, images, and A/V. Text/markdown can be edited; LSP diagnostics and formatting routes run through ViewModel operations rather than direct widget-side IO. [remote-pi-cockpit-file-media-surface]{1}

Rules:

- Keep file IO in data/domain contracts; UI asks ViewModels to read/save/mutate.
- Preserve dirty-state and draft ownership when changing tabs, paths, or preview/edit modes.
- Cancel LSP subscriptions/debounces and close old documents when paths change or widgets dispose. [remote-pi-cockpit-file-media-surface]{1}
- Guard `setState` and context use after async gaps with `mounted` / `context.mounted`.
- Treat large logs, ANSI output, markdown, SVG, and media files as untrusted display input; avoid synchronous full-tree work on hot UI paths.

## Async UI safety

Cockpit guidance is stricter than the lint: do not use `BuildContext` after `await` or inside `.then`, `.onSuccess`, `.onFailure`, `.flatMap`, or `.whenComplete` without converting to `await` plus a mounted guard. [remote-pi-cockpit-guidance]{1}

```dart
final ok = await viewModel.save();
if (!mounted) return;
if (ok) context.pop();
```

Dialogs with custom controllers should own and dispose those controllers at the call site when they are not provided by a route scope.

## Anti-patterns

- Copying `app/` mobile architecture, provider/go_router assumptions, or mobile reconnect state into `cockpit/`.
- Opening Hive boxes or spawning processes from widgets.
- Hardcoding colors/fonts instead of `context.colors` / `context.typo`.
- Using latest package docs without checking local pins and overrides.
- Letting PTYs, Pi RPC processes, LSP servers, stream subscriptions, timers, focus nodes, controllers, or window listeners survive their owner.
- Treating macOS plugin behavior as proof of Windows/Linux behavior.
- Adding cross-feature imports or centralizing new feature routes/binds in god files.
- Logging terminal contents, file contents, pairing material, or local paths unnecessarily.

## Review checklist

- [ ] Does the change stay inside `cockpit/` unless a cross-subproject boundary was explicitly scoped?
- [ ] Are feature imports still one-way (`ui -> domain <- data`) with feature/module composition only at the edge?
- [ ] Are `flutter_modular` binds/routes/ViewModels owned by the correct module and lifecycle?
- [ ] Are all async context uses guarded after async gaps?
- [ ] Are native resources disposed: PTY/processes, LSP, streams, timers, window listeners, controllers, focus nodes, media players?
- [ ] Did package examples match local pins/overrides?
- [ ] Did terminal/file/media changes account for large output, ANSI/Unicode, malformed text, and platform differences?
- [ ] Did `flutter analyze`, `flutter test`, and any relevant desktop smoke/build command pass or get reported as skipped with reason?
