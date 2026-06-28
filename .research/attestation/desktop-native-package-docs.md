---
source_handle: desktop-native-package-docs
fetched: 2026-06-28
source_url: https://pub.dev/api/packages/file_picker
provenance: source-direct
---

# Desktop native package docs attestation

## Source summary

This attestation records fetched package README/API facts for Cockpit's native desktop boundary packages: `file_picker`, `window_manager`, and `flutter_local_notifications`. Package archives were fetched from pub.dev on 2026-06-28.

## Key passages: file_picker

Source: `https://pub.dev/api/archives/file_picker-11.0.2.tar.gz`.

> The README describes `file_picker` as a package that uses the native file explorer to pick single or multiple files with extension filtering.

> Supported features include OS native pickers, multiple platforms including desktop, custom extension filtering, directory picking, save-file/save-as dialogs, and retrieving file details.

> The compatibility chart says `getDirectoryPath()` is supported on Linux, macOS, and Windows; `pickFileAndDirectoryPaths()` is macOS-only; `pickFiles()` and `saveFile()` are supported on Linux, macOS, and Windows.

## Key passages: window_manager

Source: `https://pub.dev/api/archives/window_manager-0.5.1.tar.gz`.

> The README describes `window_manager` as providing comprehensive window management for Flutter desktop applications, including control over window size, position, appearance, close behavior, and listening to events.

> Platform support table lists Linux, macOS, and Windows.

> Quick start requires `WidgetsFlutterBinding.ensureInitialized()`, `windowManager.ensureInitialized()`, `WindowOptions`, and `windowManager.waitUntilReadyToShow(... show(); focus(); ...)`.

> The README notes a planned migration to `nativeapi` and says that solution is still experimental.

## Key passages: flutter_local_notifications

Source: `https://pub.dev/api/archives/flutter_local_notifications-22.0.1.tar.gz`.

> The README describes the plugin as cross-platform for displaying local notifications.

> Supported platforms include Android, iOS, macOS, Linux, Windows, and Web.

> It warns that the minimum Flutter SDK version will be bumped occasionally as the ecosystem evolves.

> Caveats include macOS differences, Linux server-dependent limitations and no scheduled/pending notifications due to lack of a scheduler API, and Windows limitations around repeating notifications and package identity for retrieving/cancelling active notifications.

## Notes for Remote Pi

Cockpit's local pins are older than some current docs (`file_picker`, `window_manager`, `flutter_local_notifications`), so package APIs should be checked against the local lockfile before applying latest examples. Native boundary behavior needs per-platform smoke tests.
