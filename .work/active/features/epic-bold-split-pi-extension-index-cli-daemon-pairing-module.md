---
id: epic-bold-split-pi-extension-index-cli-daemon-pairing-module
kind: feature
stage: drafting
tags: [refactor, bold, pi-extension]
parent: epic-bold-split-pi-extension-index
depends_on: [epic-bold-split-pi-extension-index-composition-root]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Split pi-extension index — CLI / daemon / pairing module

## Brief
CLI/command (`remote-pi` command + `if/else` router at `index.ts:1635-1688`),
daemon/cron, and pairing extracted from `index.ts` as a named module. Globals
`_pi`, `_stopAutoListener`, `_cachedEd25519`, `_selfRevoke`, `_cwdLock`,
`_lockedName` (`index.ts:547-585`) become this module's private state. The
pairing path stays paired with the owner-multiplexer module's peer attachment.

## Epic context
- Parent epic: `epic-bold-split-pi-extension-index`
- Position: consumer of `composition-root`.

## Foundation references
- Evidence: `pi-extension/src/index.ts:547-585`, `:1635-1688`;
  `pi-extension/src/daemon/`, `pi-extension/src/pairing/`.

<!-- /agile-workflow:refactor-design pins the module boundary. -->
