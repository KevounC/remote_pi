---
source_handle: flutter-desktop-support
fetched: 2026-06-28
source_url: https://raw.githubusercontent.com/flutter/website/main/sites/docs/src/content/platform-integration/desktop.md
provenance: source-direct
---

# Flutter desktop support attestation

## Source summary

Flutter's desktop support documentation states that Flutter can compile native Windows, macOS, and Linux desktop apps and that desktop support extends to plugins for those platforms.

## Key passages

> Flutter provides support for compiling a native Windows, macOS, or Linux desktop app.

> Flutter's desktop support also extends to plugins—you can install existing plugins that support the Windows, macOS, or Linux platforms, or you can create your own.

> To create a new application that includes desktop support... `flutter run -d windows`, `flutter run -d macos`, `flutter run -d linux`.

> `flutter build windows`, `flutter build macos`, `flutter build linux`.

## Notes for Remote Pi

Cockpit is macOS-first but uses Flutter desktop plugin surfaces that may differ across Windows/Linux/macOS, so desktop plugin changes need platform smoke checks rather than mobile-only confidence.
