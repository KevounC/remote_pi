---
source_handle: flutter-app-lifecycle
fetched: 2026-06-28
source_url: https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html
provenance: source-direct
substrate_confidence: source-direct
---

# Flutter `AppLifecycleState`

Paraphrased summary: Flutter exposes application lifecycle changes through `AppLifecycleState`; apps can observe the current state through lifecycle listeners or binding observers. The lifecycle docs warn that applications should not rely on receiving every possible notification, because some states may be skipped when the app is killed abruptly or the environment changes quickly.

## Key passages

- The current lifecycle state can be obtained from `SchedulerBinding.instance.lifecycleState`; changes can be observed with `AppLifecycleListener` or `WidgetsBindingObserver.didChangeAppLifecycleState`.
- Flutter lifecycle states model foreground/background/visibility/interactivity across platforms rather than guaranteeing every native transition is delivered.
- The docs state that applications should not rely on receiving all possible notifications; termination, task-manager kills, power loss, or rapid unscheduled disassembly may send no notification and some states may be skipped.

## Structural metadata

- Source type: Flutter API documentation
- Relevant APIs: `AppLifecycleState`, `AppLifecycleListener`, `WidgetsBindingObserver.didChangeAppLifecycleState`, `SchedulerBinding.lifecycleState`.
