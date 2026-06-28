---
source_handle: hive-2-2-hive-flutter-1-1
fetched: 2026-06-28
source_url: https://pub.dev/api/archives/hive-2.2.3.tar.gz
provenance: source-direct
---

# Hive 2.2.3 / hive_flutter 1.1.0 attestation

## Source summary

The fetched Hive and hive_flutter sources describe boxes as the persistence primitive. `Hive.openBox`, `Hive.box`, `Hive.close`, and `Box.watch` are core APIs; `hive_flutter` adds `Hive.initFlutter` and `box.listenable()` for Flutter widgets.

## Key passages

> Hive README examples use `var box = await Hive.openBox('myBox')`, `Hive.box('myBox')`, `box.put`, `box.get`, and `box.delete`.

> Hive README says boxes are cached and fast enough to be used directly in Flutter widget `build()` methods.

> `hive/lib/src/hive.dart` declares `openBox`, `openLazyBox`, `box`, `lazyBox`, `isBoxOpen`, `close`, and `deleteBoxFromDisk`.

> `hive_flutter/lib/src/hive_extensions.dart` defines `initFlutter([String? subDir])` and calls `WidgetsFlutterBinding.ensureInitialized()` before initializing Hive.

> `hive_flutter/lib/src/box_extensions.dart` defines `box.listenable({List<dynamic>? keys})`, backed by `box.watch()` subscriptions filtered by keys when provided.

## Notes for Remote Pi

Cockpit opens Hive boxes during `main()` or async module builders and injects repositories/stores rather than opening boxes inside widgets. Debug uses its own Hive subdirectory to avoid colliding with production boxes.
