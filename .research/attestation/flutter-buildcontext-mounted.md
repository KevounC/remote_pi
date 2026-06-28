---
source_handle: flutter-buildcontext-mounted
fetched: 2026-06-28
source_url: https://api.flutter.dev/flutter/widgets/BuildContext/mounted.html
provenance: source-direct
substrate_confidence: source-direct
---

# Flutter `BuildContext.mounted`

Paraphrased summary: Flutter documents `BuildContext.mounted` as the validity guard for using a `BuildContext`. Accessing context properties or methods is valid only while `mounted` is true. After an asynchronous gap, code should check `mounted` before using the context.

## Key passages

- Accessing properties of `BuildContext` or calling methods on it is only valid while `mounted` is true.
- If `mounted` is false, assertions will trigger.
- Once unmounted, a context will never become mounted again.
- If a `BuildContext` is used across an asynchronous gap, the docs recommend checking `mounted` before interacting with it.

## Structural metadata

- Source type: Flutter API documentation
- Relevant API: `BuildContext.mounted`.
