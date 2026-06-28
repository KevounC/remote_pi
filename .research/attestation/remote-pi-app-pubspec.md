---
source_handle: remote-pi-app-pubspec
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/app/pubspec.yaml
provenance: source-direct
substrate_confidence: source-direct
---

# Remote Pi app `pubspec.yaml`

Paraphrased summary: The Flutter app package is private, versioned `1.1.1+6`, targets Dart SDK `^3.11.5`, and declares the mobile app's dependency set. High-impact dependencies include `cryptography`, `mobile_scanner`, `flutter_secure_storage`, `web_socket_channel`, `go_router`, `provider`, Hive, a local `remote_pi_identity` package, `dio`, speech/image/markdown/url packages, Google Fonts, and package version detection.

## Key passages

- `publish_to: "none"` marks the app as private.
- `environment.sdk` is `^3.11.5`.
- Dependencies include `web_socket_channel: ^3.0.1`, `go_router: ^14.0.0`, `provider: ^6.1.2`, `hive: ^2.2.3`, `hive_flutter: ^1.1.0`, `flutter_secure_storage: ^9.0.0`, `dio: ^5.7.0`, `speech_to_text: ^7.0.0`, `image_picker: ^1.1.0`, `flutter_image_compress: ^2.3.0`, `gpt_markdown: ^1.1.7`, `url_launcher: ^6.3.0`, and `package_info_plus: ^8.0.0`.
- `remote_pi_identity` is a local path dependency under `packages/remote_pi_identity`.
- Dev dependencies include `flutter_test`, `fake_async`, and `flutter_lints: ^6.0.0`.

## Structural metadata

- Source type: local package manifest
- Path: `/home/agent/forks/remote_pi/app/pubspec.yaml`
