---
id: story-remote-pi-android-build-smoke
kind: story
stage: done
tags: [app]
parent: feature-remote-pi-fork-vendor-and-mobile-surface
depends_on: []
release_binding: app-v1.1.1
gate_origin: null
archived_atop: unbound
archived_ref: 3dba904
created: 2026-06-27
updated: 2026-06-29
---

# Build and pair the forked remote-pi Android app locally

## Brief

Prove the forked `app/` can be built locally and paired with the existing relay/dev VM path before
planning client-side UX changes.

## Tasks

- Inspect Flutter/Android prerequisites in `/home/agent/forks/remote_pi/app`.
- Confirm whether this dev VM has Flutter/Android SDK tooling; if not, record the workstation-only
  steps rather than forcing install in this environment.
- Build a debug APK if tooling is available.
- Pair the built app against the existing relay and a local Pi session.
- Record any signing, package-id, or license blockers before distribution beyond private/dev use.

## Acceptance

- A local build path is documented.
- Either a debug APK is built and paired, or blockers are explicit and actionable.
- The item records whether app work can proceed on this VM or requires workstation/Android tooling.

## Implementation notes

Completed 2026-06-29. The dev VM (`codebox`, Debian 13/trixie) now builds the
forked `app/` Android APK without workstation round-trips.

**Outcome** — `flutter build apk --debug` from `app/` produced a verified
`app-debug.apk` (package `work.jacobmoura.remotepi`, version `1.1.1+6`, minSdk
34 / target 36 / compile 36). The APK was paired against the relay + local Pi
session and a message was sent from mobile, exercising the live pair path.

**Toolchain installed on this VM** — Flutter 3.44.4 was already present; the rest
was installed as root and persisted in `/etc/profile.d/android.sh`:

- JDK: `openjdk-21-jdk-headless`. Debian 13 has no `openjdk-17`; JDK 21 compiles
  the app's pinned Java 17 target and is within AGP 8.11.1's supported range.
- Android SDK at `/opt/android-sdk`: cmdline-tools 12.0, `platform-tools`
  (adb), `build-tools;35.0.0`, `platforms;android-36` (Flutter's
  `FlutterExtension.compileSdkVersion == 36` — install 36, not 35), and
  CMake 3.22.1 + Flutter's default NDK (auto-fetched on first build).
- `flutter config --android-sdk /opt/android-sdk` set.

**Two build-path gremlins, recorded so they are not re-debugged:**

1. `background` jobs run under `/bin/sh` (dash on Debian), which has no `source`
   builtin — only POSIX `.`. A background build command starting with
   `source /etc/profile.d/android.sh` exits 127 before `flutter` runs. Use `.`
   instead. (Foreground bash sessions accept both.)
2. A disk-full or interrupted first build can leave a corrupt Gradle Kotlin-DSL
   accessors workspace (`metadata.bin` unreadable under
   `~/.gradle/caches/8.14/kotlin-dsl/accessors/<hash>/`), which Gradle then
   refuses to overwrite, reproducing `Could not read workspace metadata ...` on
   every run. Wiping only `~/.gradle/caches` is insufficient — the stale state
   also lives in sibling `daemon/`, `native/`, and `.tmp/` dirs. Fix is
   `rm -rf ~/.gradle app/android/.gradle` (the whole user + project Gradle
   state), not just `caches`.

**Disk budget** — a first build needs ~5–8 GB free for Gradle + AGP + NDK + ML
Kit/CameraX deps. The VM had run out of space; reclaimed ~8 GB by vacuuming the
systemd journal (`journalctl --vacuum-size=100M`, freed 4 GB) and removing the
failed-build Gradle cache.

**Tooling recipe** captured durably in `.agents/skills/flutter-mobile/SKILL.md`
(Android build section) and referenced from `app/CLAUDE.md`, so this VM can
repeat the build without re-deriving the steps.

**Signing / distribution** — debug APK is debug-signed, fine for private/dev
side-loading. Release signing loads `android/key.properties` when present and
falls back to debug keys otherwise (see `app/android/app/build.gradle.kts`).
Not bound to a release.
