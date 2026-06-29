---
name: flutter-mobile
description: Remote Pi Flutter mobile app reference. Read before editing or reviewing app/ code, mobile lifecycle, provider/ViewModels, routing, relay WebSocket reconnect, room/session state, secure storage, Hive cache, or UI async safety.
updated: 2026-06-28
---

# Flutter Mobile App Reference

> Local scope: `app/`
> Versions/context: Flutter 3.41+ / Dart 3.11+ by project guidance, Dart SDK `^3.11.5`; key package pins include `provider ^6.1.2`, `go_router ^14.0.0`, `web_socket_channel ^3.0.1`, `flutter_secure_storage ^9.0.0`, and Hive 2.x. [remote-pi-app-guidance]{1} [remote-pi-app-pubspec]{1}
> Source basis: `app/CLAUDE.md`, `app/pubspec.yaml`, `ConnectionManager`, `WsTransport`, `SyncService`, and Flutter/package docs attested in `.research/attestation/`.

## When to load

- Any edit or review under `app/`.
- Any change involving foreground/background behavior, reconnect, WebSocket liveness, pairing, session switching, `Working`/idle rendering, room metadata, Hive cache, provider/ViewModels, or route guards.
- Any UI code that uses `BuildContext` after async work.

## Commands

Run from `app/`: [remote-pi-app-guidance]{1}

```bash
flutter pub get
flutter analyze
flutter test
dart format .
flutter build apk --debug
flutter build ios --no-codesign
```

Do not commit `build/`, `.dart_tool/`, `ios/Pods/`, secrets, device-local files, or generated artifacts.

### Android APK build on the dev VM (`codebox`)

The dev VM can build Android APKs without workstation round-trips. Toolchain is
installed and persisted; these notes are so a fresh agent does not re-derive it.

**Toolchain (already installed as root, persisted in `/etc/profile.d/android.sh`):**

- Flutter 3.44.4 at `/opt/flutter` (Dart 3.12.2).
- JDK `openjdk-21-jdk-headless`. Debian 13/trixie ships no `openjdk-17`; JDK 21
  compiles the app's pinned Java 17 target and is within AGP 8.11.1's supported
  range. `JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64`.
- Android SDK at `/opt/android-sdk`: cmdline-tools 12.0, `platform-tools`
  (adb), `build-tools;35.0.0`, `platforms;android-36`, CMake 3.22.1, and
  Flutter's default NDK (auto-fetched on first build).
- `flutter config --android-sdk /opt/android-sdk` is set.

  Why **API 36**, not 35: `app/android/app/build.gradle.kts` sets
  `compileSdk = flutter.compileSdkVersion`, and Flutter 3.44.4's
  `FlutterExtension.kt` pins `compileSdkVersion = 36`. Install `platforms;android-36`.
  `minSdk = 34` is a floor and needs no separate platform install.

**Build commands (run from `app/`):**

```bash
# debug — fat (all ABIs, ~184 MB), debug-signed, fastest to iterate
flutter build apk --debug

# release, one APK per ABI — small. Build the one matching the device:
#   arm64-v8a   → modern Android phones (Pixel etc.)        ~31 MB
#   armeabi-v7a → old 32-bit ARM devices                     ~27 MB
#   x86_64      → emulators                                  ~33 MB
flutter build apk --release --split-per-abi

# release, single fat APK (all ABIs) — ~3x the per-ABI size
flutter build apk --release
```

Output lands in `app/build/app/outputs/flutter-apk/`. Side-load with
`adb install <apk>` (USB debugging / ADB debugging on; uninstall any
same-package build signed with a different key first to avoid
`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

**Two build-path gremlins, recorded so they are not re-debugged:**

1. **`.` not `source` in background/dash jobs.** The pi `background` tool runs
   commands under `/bin/sh` (dash on Debian), which has no `source` builtin —
   only POSIX `.`. A background build command starting with
   `source /etc/profile.d/android.sh` exits 127 before `flutter` runs. Use `.`
   in any sh/dash context. Foreground bash sessions accept both.
2. **Corrupt Gradle Kotlin-DSL workspace after a failed/disk-full build.** An
   interrupted first build can leave `metadata.bin` unreadable under
   `~/.gradle/caches/8.14/kotlin-dsl/accessors/<hash>/`; Gradle refuses to
   overwrite it and reproduces `Could not read workspace metadata ...` on every
   run. Wiping only `~/.gradle/caches` is insufficient — stale state also lives
   in sibling `daemon/`, `native/`, `.tmp/`, and the project `app/android/.gradle`.
   Fix: `rm -rf ~/.gradle app/android/.gradle` (the whole user + project Gradle
   state), then rebuild.

**Disk budget:** a first build needs ~5–8 GB free for Gradle + AGP + NDK + ML
Kit/CameraX deps. If the VM is low, reclaim from the systemd journal
(`journalctl --vacuum-size=100M`) and the apt cache (`apt-get clean`) first.

**Release signing:** loads `android/key.properties` when present; falls back to
debug keys otherwise (see `app/android/app/build.gradle.kts`). Debug builds are
fine for private/dev side-loading.

## App architecture

Remote Pi's app is the mobile iOS/Android client for pairing, session lists, streaming chat, and tool approval cards. [remote-pi-app-guidance]{1}

Layer direction is load-bearing:

```text
ui ──► domain ◄── data
        ▲
        │
     config injects
     routing composes
```

- `domain/` must remain Flutter/network/storage-free and must not import `data/`, `ui/`, `routing`, or `config`. [remote-pi-app-guidance]{1}
- `data/` implements adapters/repositories against domain contracts; it must not import UI.
- `ui/` talks to domain/use cases through ViewModels; pages should not instantiate ViewModels directly.
- `config/` owns registration/injection; `routing/` composes routes and ViewModels through Provider.
- Read the nearest `CLAUDE.md` before editing layer directories (`lib/data`, `lib/domain`, `lib/routing`, `lib/ui`, `lib/config`).

## Async UI safety

Flutter documents `BuildContext` as valid only while `mounted` is true, and recommends a mounted check after an async gap before interacting with the context. [flutter-buildcontext-mounted]{1} The Dart lint makes the same distinction: use `State.mounted` when using a `State` object's context, and `context.mounted` for other `BuildContext` values. [dart-use-build-context-synchronously]{1}

```dart
// Correct: await + guard before context use.
final result = await viewModel.doSomething();
if (!mounted) return; // StatefulWidget State
// if (!context.mounted) return; // other BuildContext values
ScaffoldMessenger.of(context).showSnackBar(...);
```

Remote Pi's app guidance is stricter than the lint because callback chains can hide context use from analysis: do not use `context` inside `.onSuccess`, `.onFailure`, `.flatMap`, `.then`, or `.whenComplete`; turn those paths into `await` plus a mounted guard. [remote-pi-app-guidance]{1}

## Provider / ViewModel usage

Provider's consumption APIs are: `watch` listens and rebuilds, `read` returns without listening, and `select` listens to a selected projection. [provider-package]{1}

```dart
final vm = context.watch<ChatViewModel>();
final isWorking = context.select<ChatViewModel, bool>((vm) => vm.isWorking);

onPressed: () {
  context.read<ChatViewModel>().send(text);
}
```

Rules:

- Use `watch` only when the whole widget should rebuild on any `notifyListeners()` from that ViewModel.
- Prefer `select` for hot room/session fields such as connection, presence, and `working` to avoid whole-list rebuilds.
- Use `read` in callbacks/event handlers, not as a build-time reactive dependency; provider docs note `read` does not rebuild and should not be called inside `build`. [provider-package]{1}
- Use default Provider constructors when creating a new object; use `.value` only for an existing object instance. [provider-package]{1}
- Keep ViewModel disposal owned by Provider/DI; avoid manual singleton retention in widgets.

## Routing

This app pins `go_router ^14.0.0`; current pub.dev docs list a newer 17.x line, so check local generated lock/API before copying newly documented patterns. [go-router-package]{1} [remote-pi-app-pubspec]{1}

- Use `GoRoute` path templates and `GoRouterState` path/query parameters for route data.
- Use redirects for auth/pairing/sync guards only when they are pure functions of app state; avoid async side effects in redirects.
- `ShellRoute`/multi-Navigator patterns exist, but do not introduce them unless the UI actually needs independent navigation stacks. [go-router-package]{1}
- Route builders may receive a `BuildContext`; all async context rules still apply.

## WebSocket and lifecycle behavior

`IOWebSocketChannel.connect` wraps `dart:io` WebSocket connections. Its `pingInterval` closes the socket with a going-away code when pings are not answered, and connection errors surface on the stream before close. [web-socket-channel-io]{1}

Remote Pi app transport rules:

- `WsTransport` uses `IOWebSocketChannel.connect(..., pingInterval: 20s)` for app↔relay TCP liveness; do not confuse this with protocol-level app↔Pi ping/pong. [web-socket-channel-io]{1} [remote-pi-app-transport-state]{1}
- `ConnectionManager` is the app-side owner of connection status, retry/backoff, presence, rooms, and liveness snapshots. [remote-pi-app-transport-state]{1}
- Presence and room streams emit full snapshots; consumers should treat each emission as canonical, not as a partial patch. [remote-pi-app-transport-state]{1}
- On reconnect, `ConnectionManager` replays presence + room subscriptions and sends check frames; new state must hydrate from relay snapshots, not from sticky UI booleans. [remote-pi-app-transport-state]{1}
- `isRoomLive` and `isRoomWorking` intentionally return false while the app is not `StatusOnline`; stale cached truth must not render as live/working. [remote-pi-app-transport-state]{1}

Flutter lifecycle notifications are useful but not complete: apps should not rely on receiving every state notification, and states can be skipped during abrupt termination. [flutter-app-lifecycle]{1} `AppLifecycleListener` is the current listener API for lifecycle transitions. [flutter-app-lifecycle-listener]{1}

Practical rule: foreground/resume should re-check relay/session state; background/pause should not be the only path that clears or persists critical state.

## Room/session state rules

- `ConnectionStatus`: `noPeer`, `connecting`, `online`, `retrying`, `offline` are distinct states; UI must not collapse all non-online states into one generic failure. [remote-pi-app-transport-state]{1}
- `_roomsByPeer` is cached room knowledge; `_liveRoomIds` is current reachability. A cached room can be known but offline. [remote-pi-app-transport-state]{1}
- `RoomsSnapshot` is authoritative for live room metadata, including `working`; event deltas must converge to snapshot truth. [remote-pi-app-transport-state]{1}
- `markRoomWorking` is an active-room backstop so a missed or delayed relay metadata update cannot leave the active chat/Home tile stuck working. [remote-pi-app-transport-state]{1}
- `SyncService` owns local message/session writes; UI should read through read repositories/ViewModels rather than writing Hive directly.

## Mobile lifecycle gotchas

- Android may restrict background work, including network access for restricted apps except while foreground; choose proper background-work APIs rather than assuming an always-live socket. [android-background-restrictions]{1}
- iOS may suspend the app after backgrounding; no app process code runs while suspended and socket resources may be reclaimed. [apple-networking-multitasking]{1}
- Therefore the app must tolerate silent disconnect, missed lifecycle callbacks, and stale sockets. Resume/reconnect hydration is the safety path, not background continuity.
- Do not wait for network in a background-transition callback; Apple's note warns that waiting in background transition paths can hit the watchdog. [apple-networking-multitasking]{1}

## Anti-patterns

- Using `BuildContext` after `await` or callback-chain async gaps without `mounted` / `context.mounted`.
- Rendering cached `working: true` while disconnected or before the reconnect snapshot arrives.
- Treating a relay WebSocket connection as proof that the Pi room is alive; app↔relay and app↔Pi liveness are separate.
- Applying package-doc examples from newer `go_router`/Flutter versions without checking local pins.
- Updating UI directly from `data/` streams instead of ViewModels/read repositories.
- Writing partial event patches into UI state without an authoritative snapshot recovery path.
- Letting stream subscriptions, timers, or pending send timers survive session switch or dispose.
- Logging message bodies, key material, or image payloads while debugging transport.

## Review checklist

- [ ] Are layer imports still one-way (`ui -> domain <- data`, config/routing compose only)?
- [ ] Are all async context uses guarded after every async gap?
- [ ] Does UI distinguish connected idle, working, reconnecting/offline, and stale/unknown?
- [ ] Does reconnect replay subscriptions and hydrate from authoritative snapshots?
- [ ] Can `working` converge false after agent done, error, cancel, timeout, reconnect, app background/resume, and session switch?
- [ ] Are stream subscriptions/timers cancelled on dispose and session switch?
- [ ] Are hot widgets using `select` or narrow ViewModel fields instead of broad rebuilds?
- [ ] Did `flutter analyze`, `flutter test`, and relevant build smoke pass?
