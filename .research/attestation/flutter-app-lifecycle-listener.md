---
source_handle: flutter-app-lifecycle-listener
fetched: 2026-06-28
source_url: https://api.flutter.dev/flutter/widgets/AppLifecycleListener-class.html
provenance: source-direct
substrate_confidence: source-direct
---

# Flutter `AppLifecycleListener`

Paraphrased summary: `AppLifecycleListener` is Flutter's object API for subscribing to application lifecycle transitions. It provides an `onStateChange` callback and more specific callbacks around foreground/background/visibility/exit transitions, delegating to `didChangeAppLifecycleState` under the widgets binding lifecycle notification path.

## Key passages

- The class is described as a listener for changes in application lifecycle state.
- To listen for changes, define an `onStateChange` callback; the AppLifecycleState enum documents the states.
- `didChangeAppLifecycleState` is called when the system puts the app in the background or returns it to foreground.
- The listener must be disposed when no longer needed, like other lifecycle-bound listener objects.

## Structural metadata

- Source type: Flutter API documentation
- Relevant APIs: `AppLifecycleListener`, `onStateChange`, `didChangeAppLifecycleState`, `dispose`.
