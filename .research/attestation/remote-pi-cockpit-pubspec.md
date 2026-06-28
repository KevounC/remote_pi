---
source_handle: remote-pi-cockpit-pubspec
fetched: 2026-06-28
source_path: cockpit/pubspec.yaml
provenance: source-direct
---

# Remote Pi cockpit pubspec attestation

## Source summary

`cockpit/pubspec.yaml` pins the desktop stack: Dart SDK `^3.11.5`, `shadcn_flutter 0.0.52`, `flutter_modular ^7.1.0`, Hive, file/window/terminal/native packages, media/markdown/rendering packages, notifications, update support, and several git overrides for forked dependencies.

## Key passages

> `environment: sdk: ^3.11.5`

> `shadcn_flutter: 0.0.52` with a note that it is an exact pin because the package is pre-1.0 and API-churn-prone.

> `flutter_modular: ^7.1.0` with a note that it replaces provider + auto_injector + go_router for DI/routing/page-scoped state.

> Terminal stack: `xterm: ^4.0.0` and `kyroon_pty: ^1.0.4`, with a dependency override for a `xterm.dart` fork that draws block/box glyphs procedurally and a `kyroon_pty` fork at ref `v1.0.5`.

> Native/file surfaces include `file_picker`, `window_manager`, `pasteboard`, `desktop_drop`, `flutter_local_notifications`, `media_kit`, `auto_updater`, `ffi`, and `win32`.

## Checked package-version facts

From `cockpit/pubspec.lock` plus pub.dev package APIs fetched on 2026-06-28:

- `shadcn_flutter`: locked/latest `0.0.52`.
- `flutter_modular`: locked/latest `7.1.0`.
- `file_picker`: locked `8.3.7`, latest `11.0.2`.
- `window_manager`: locked `0.4.3`, latest `0.5.1`.
- `xterm`: git override locked `4.0.0`, pub latest `4.0.0`.
- `kyroon_pty`: git override locked `1.0.5`, pub latest `1.0.4`.
- `flutter_local_notifications`: locked `18.0.1`, latest `22.0.1`.
- `hive`: locked/latest `2.2.3`; `hive_flutter`: locked/latest `1.1.0`.
- `desktop_drop`: locked `0.5.0`, latest `0.7.1`; `pasteboard`: locked `0.4.0`, latest `0.5.0`.
- `gpt_markdown`: git override locked `1.2.2`, pub latest `1.1.7`.
- `media_kit`: locked/latest `1.2.6`; `media_kit_video`: locked `1.3.1`, latest `2.0.1`.

## Notes for Remote Pi

Agents must follow local pins and overrides when editing, not blindly copy latest-doc examples. The drift list is useful for upgrade research, not automatic permission to upgrade packages.
