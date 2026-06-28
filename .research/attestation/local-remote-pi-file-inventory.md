---
source_handle: local-remote-pi-file-inventory
fetched: 2026-06-28
source_path: local filesystem inventory via find/python line counts
provenance: source-direct
---

# File inventory attestation

1. A file inventory excluding common build/generated directories found primary source extensions: `.dart` 382 files / about 71,700 lines; `.ts` 84 files / about 23,808 lines; `.tsx` 32 files / about 5,995 lines; `.rs` 27 files / about 5,117 lines; `.md` 182 files / about 24,814 lines.
2. Manifests found are `app/pubspec.yaml`, `app/packages/remote_pi_identity/pubspec.yaml`, `cockpit/pubspec.yaml`, `pi-extension/package.json`, `relay/Cargo.toml`, `rp-s3/Cargo.toml`, and `site/package.json`.
3. The source distribution means Dart/Flutter is the largest code surface by line count, TypeScript is the extension/site surface, and Rust is a smaller but security/routing-critical surface.
