---
source_handle: local-remote-pi-manifests
fetched: 2026-06-28
source_path: package manifests: app/pubspec.yaml, cockpit/pubspec.yaml, pi-extension/package.json, relay/Cargo.toml, rp-s3/Cargo.toml, site/package.json
provenance: source-direct
---

# Manifest attestation

1. `pi-extension/package.json` declares a Node/TypeScript ESM package (`remote-pi` 0.5.3), Node `>=20`, TypeScript 6.x, Vitest 4.x, and dependencies including `@earendil-works/pi-coding-agent`, MCP SDK, `@napi-rs/keyring`, `@noble/ed25519`, `ws`, `zod`, `typebox`, `croner`, and `qrcode-terminal`.
2. `relay/Cargo.toml` declares a Rust 2024 crate depending on `axum` 0.7 with WebSockets, `tokio` with full features, `rusqlite`, `ed25519-dalek`, `serde`, `serde_json`, `tracing`, `thiserror`, and `anyhow`.
3. `app/pubspec.yaml` declares Flutter/Dart SDK `^3.11.5` and dependencies including `cryptography`, `mobile_scanner`, `flutter_secure_storage`, `web_socket_channel`, `go_router`, `provider`, `auto_injector`, `hive`, `dio`, `speech_to_text`, `image_picker`, `flutter_image_compress`, `gpt_markdown`, and `google_fonts`.
4. `cockpit/pubspec.yaml` declares Flutter/Dart SDK `^3.11.5` and a desktop-oriented dependency set including `shadcn_flutter`, `flutter_modular`, `file_picker`, `hive`, `xterm`, `kyroon_pty`, `media_kit`, `highlight`, `pasteboard`, `desktop_drop`, `window_manager`, `auto_updater`, `win32`, and `ffi`.
5. `site/package.json` declares Next 16, React 19, Tailwind 4, TypeScript 5, and ESLint for the website.
6. `rp-s3/Cargo.toml` declares a small Rust 2021 Axum/Tokio/tower-http artifact server.
