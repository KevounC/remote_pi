---
id: story-api-reference-flutter-mobile-stack
kind: story
stage: drafting
tags: [app, research, docs]
parent: feature-agent-reference-surface
depends_on: [story-research-platform-agent-reference-patterns]
created: 2026-06-27
updated: 2026-06-27
---

# API reference for Flutter mobile app stack

Create a platform-style stack reference for `app/`, with emphasis on mobile lifecycle, reconnect behavior, and state rendering for remote coding sessions.

## Candidate coverage

- Flutter/Dart current lifecycle APIs relevant to foreground/background/resume, app suspension, `BuildContext.mounted`, and async UI safety.
- State management in this app: `ChangeNotifier` + `provider`, ViewModel boundaries, `context.select/watch/read` patterns.
- Routing: `go_router` usage and navigation gotchas.
- WebSocket/reconnect: `web_socket_channel`, stream subscriptions, close/error handling, reconnect hydration.
- Persistence/security: `flutter_secure_storage`, Hive cache, owner key identity package.
- Mobile capabilities already used: QR scanning, speech-to-text, image picker/compression, notifications/update notices if relevant.
- Test/dev cycle: `flutter pub get`, `flutter analyze`, `flutter test`, `dart format .`, debug Android build smoke.

## Known gotchas to include

- Do not use `BuildContext` after async gaps without `mounted`/`context.mounted` guard; chained callbacks can bypass lint coverage.
- Room/session metadata must be modeled as authoritative snapshots plus sequenced deltas, not sticky UI booleans.
- Mobile UI should distinguish `connected idle`, `working`, `disconnected`, and `unknown/stale`.
- Reconnect must hydrate current server state rather than trusting cached `working: true`.

## Acceptance

- A reference skill/doc exists and is linked from `AGENTS.md` or app guidance.
- Current Flutter/mobile docs are consulted for lifecycle and background/reconnect behavior.
- The reference is specific enough to guide the `Working` stuck bug and future mobile refactors.
