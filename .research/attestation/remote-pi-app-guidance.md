---
source_handle: remote-pi-app-guidance
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/app/CLAUDE.md
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi app `CLAUDE.md`

Paraphrased summary: The app guidance identifies the mobile client stack, layer boundaries, common commands, and critical async `BuildContext` rule. It frames `app/` as the mobile iOS/Android client for pairing, session listing, chat streaming, and tool approvals.

## Key passages

- Stack includes Flutter 3.41+ / Dart 3.11+, iOS + Android, `ChangeNotifier` + `provider`, `auto_injector`, `go_router`, typed `Result<T,E>`, crypto bindings, and `web_socket_channel` or similar.
- Commands include `flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`, `dart format .`, `flutter build ios --no-codesign`, and `flutter build apk --debug`.
- Layer direction is `ui -> domain <- data`, with `config` injecting all layers and `routing` composing routes/ViewModels.
- `domain/` must not import `data/`, `ui/`, `routing`, or `config`; `data/` imports domain contracts, not UI; UI consumes domain through ViewModels.
- ViewModels are registered in `config/` and injected in `routing/` via Provider; pages should not instantiate ViewModels directly.
- The critical async rule forbids context use inside chained async callbacks such as `.onSuccess`, `.onFailure`, `.flatMap`, `.then`, or `.whenComplete`; use `await` plus `mounted`/`context.mounted` guard instead.

## Structural metadata

- Source type: local project guidance
- Path: `/home/agent/forks/remote_pi/app/CLAUDE.md`
