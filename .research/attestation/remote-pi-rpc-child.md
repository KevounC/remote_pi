---
source_handle: remote-pi-rpc-child
fetched: 2026-06-28
source_path: /home/agent/forks/remote_pi/pi-extension/src/daemon/rpc_child.ts
provenance: source-direct
---

# Remote Pi daemon RPC child

Paraphrased summary: `src/daemon/rpc_child.ts` wraps a `pi --mode rpc -e <extension>` child for supervisor/daemon operation. It defines the sentinel exit code used by the extension to request a fresh daemon session after app-triggered `session_new`.

## Key passages

- `RpcChild` boots Pi with `REMOTE_PI_DAEMON=1` so the extension can distinguish daemon/RPC mode from interactive mode.
- `EXIT_DAEMON_FRESH_SESSION` is defined as `42`.
- The child process reports exits with code/signal/crash metadata so the supervisor can decide whether to restart.
- The file contains platform-specific logic for resolving the `pi` executable on Windows without relying on `shell:true`.

## Structural metadata

- Source type: TypeScript source
- Path: `/home/agent/forks/remote_pi/pi-extension/src/daemon/rpc_child.ts`
