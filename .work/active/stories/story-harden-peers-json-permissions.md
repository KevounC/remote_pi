---
id: story-harden-peers-json-permissions
kind: story
stage: implementing
tags: [pi-extension, security]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Harden peers.json file permissions

`pi-extension/src/pairing/storage.ts` writes `~/.pi/remote/peers.json` without an explicit mode, so paired-owner metadata can inherit permissive umask permissions.

## Acceptance Criteria

- [ ] `peers.json` writes are atomic or otherwise safe and use `0600` permissions on POSIX where applicable.
- [ ] Existing readable files are chmodded/migrated on update/read if needed.
- [ ] Add tests for file mode behavior where the test environment supports POSIX modes.
