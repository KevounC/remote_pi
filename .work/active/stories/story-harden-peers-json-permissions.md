---
id: story-harden-peers-json-permissions
kind: story
stage: done
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

- [x] `peers.json` writes are atomic or otherwise safe and use `0600` permissions on POSIX where applicable.
- [x] Existing readable files are chmodded/migrated on update/read if needed.
- [x] Add tests for file mode behavior where the test environment supports POSIX modes.

## Implementation notes

Changed `pi-extension/src/pairing/storage.ts` to reuse private-directory hardening for `~/.pi/remote`, chmod existing `peers.json` on reads, and write peer updates via same-directory temp files with `0600` mode followed by atomic `rename` and final chmod. Added `pi-extension/src/pairing/storage.test.ts` coverage for private writes, permissive-file hardening on read, and permissive-file migration on update with POSIX mode assertions gated off Windows.

Verification from `pi-extension/`:

- `corepack pnpm typecheck` — passed.
- `corepack pnpm test -- src/pairing/storage.test.ts` — passed; Vitest ran 33 files / 580 tests passed, 3 skipped.
- `corepack pnpm test` — passed; 33 files / 580 tests passed, 3 skipped.

## Review (2026-06-28)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Fresh-context review of commit `3c9d2e3`; correctness, tests, security/privacy, design alignment, and foundation-doc drift lenses checked. Verification evidence from implementation notes accepted; tests were not re-run.
