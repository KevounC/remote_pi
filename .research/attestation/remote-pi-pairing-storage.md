---
source_handle: remote-pi-pairing-storage
fetched: 2026-06-28
source_path: /home/agent/projects/remote_pi/pi-extension/src/pairing/storage.ts
provenance: source-direct
---

# Remote Pi pairing storage

Paraphrased summary: Pairing storage owns the long-term Pi identity and paired peer records. It prefers OS keyring storage for the Ed25519 identity, migrates a legacy service name when present, falls back to a chmod-protected file on headless/no-keyring systems, and stores paired peers under the user's Pi remote directory.

## Key passages

- The primary keyring service/account is `dev.remotepi.pi` / `longterm-ed25519`; the file contains a legacy service path for migration from `dev.remotepi.mac`.
- Headless/no-secret-service fallback writes `~/.pi/remote/identity.json` with restrictive permissions; the parent remote directory is also created with restrictive permissions.
- Transient keyring read/write failures are retried rather than immediately regenerating identity.
- Paired peers are stored in `~/.pi/remote/peers.json`; helper functions add/list/remove peers and preserve global pairing state across extension sessions.
- Storage failures are surfaced through explicit error paths such as `KeyringUnavailableError` rather than silently creating a new identity in every case.

## Structural metadata

- Source type: TypeScript source
- Path: `/home/agent/projects/remote_pi/pi-extension/src/pairing/storage.ts`
