---
id: story-remote-pi-local-vendor-switch
kind: story
stage: done
tags: [pi-extension, workflow]
parent: feature-remote-pi-fork-vendor-and-mobile-surface
depends_on: []
created: 2026-06-27
updated: 2026-06-27
---

# Switch Pi to local remote-pi fork for development

## Brief

For development, load `remote-pi` from `/home/agent/forks/remote_pi/pi-extension` instead of the
installed npm package `npm:remote-pi@0.5.3`. Preserve a clear rollback path to the npm package.

## Design decisions
- Use Pi's supported **local path package source** in the user-global settings file, not a project-local override.
- Replace the existing `remote-pi` source with the absolute path `/home/agent/forks/remote_pi/pi-extension`.
- Keep `npm:remote-pi@0.5.3` recorded here as the rollback source string.
- Build the fork first so `dist/` exists; the checkout already builds cleanly with `corepack pnpm build`.
- Do not touch the fork source for this story unless a build/install check requires it.

## Architectural choice
Pi already supports local-path package sources in `~/.pi/agent/settings.json`, so the cleanest vendor override is a single source swap in that file. That keeps the change machine-wide for the current user, avoids `.pi/settings.json`, and preserves a one-line rollback to the npm package.

Rejected alternatives:
- Project-local `.pi/settings.json`: wrong scope for a user-machine override.
- Symlink/manual `node_modules` swap: bypasses Pi's package model and makes rollback brittle.
- Git remote pinning: adds network drift and is not the requested dev-local fork path.

## Implementation order
1. Ensure `/home/agent/forks/remote_pi/pi-extension/dist/` exists via `corepack pnpm build`.
2. Update `~/.pi/agent/settings.json` so the `packages` entry for `remote-pi` points at `/home/agent/forks/remote_pi/pi-extension` instead of `npm:remote-pi@0.5.3`.
3. Restart Pi or run `/reload`, then verify `/remote-pi status` and the agent-network tools resolve from the forked checkout.
4. If verification fails, restore `npm:remote-pi@0.5.3` in the same settings file and retry.

## Testing
- `corepack pnpm build` in `/home/agent/forks/remote_pi/pi-extension` succeeds and leaves `dist/index.js` present.
- `pi list` (or equivalent settings inspection) shows `/home/agent/forks/remote_pi/pi-extension` as the active `remote-pi` source.
- After restart/reload, `/remote-pi status` works and loads from the fork.
- `agent_send` / `agent_request` still appear and function after the source swap.
- Rollback smoke: restoring `npm:remote-pi@0.5.3` brings Pi back to the installed package.

## Implementation notes
- 2026-06-27: Rebuilt `/home/agent/forks/remote_pi/pi-extension` with `corepack pnpm build`; TypeScript build exited 0 and `dist/index.js` passes `node --check`.
- 2026-06-27: Updated user-global `~/.pi/agent/settings.json` so package entry 4 is `/home/agent/forks/remote_pi/pi-extension`; rollback source remains `npm:remote-pi@0.5.3`.
- 2026-06-27: Wrote rollback backup at `~/.pi/agent/settings.json.bak-remote-pi-vendor-switch`.
- 2026-06-27: `pi list` reports `/home/agent/forks/remote_pi/pi-extension` as the active user package source.
- 2026-06-27: After the source-fix rebuild, `pi list` reports `/home/agent/forks/remote_pi/pi-extension` as the active package source, and the live resumed remote-pi session emitted `Mesh name: SNC` plus `Relay connected` rather than falling back to the npm package path. Rollback remains the recorded `npm:remote-pi@0.5.3` source string.

## Risks
- `/reload` may not retarget the package source swap; a full Pi restart may be required.
- If `dist/` is missing, the local package will not load, so the build step is mandatory before switching.
- Accidentally introducing a project-local `.pi/settings.json` would violate the scope and must be avoided.

## Review (2026-06-27)

**Verdict**: Approve

**Blockers**: none
**Important**: none
**Nits**: none

**Notes**: Substrate story review. Confirmed the item records the local fork source swap, rollback source (`npm:remote-pi@0.5.3`), build evidence, `pi list` evidence, and live reload smoke from the forked package. No code changes belong to this story; parent remains active because sibling stories are still drafting/reviewing.
