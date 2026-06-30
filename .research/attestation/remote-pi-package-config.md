---
source_handle: remote-pi-package-config
fetched: 2026-06-28
source_path: /home/agent/projects/remote_pi/pi-extension/package.json
provenance: source-direct
---

# Remote Pi pi-extension package configuration

Paraphrased summary: The `pi-extension/package.json` declares `remote-pi` as an ESM package targeting Node >=20, with TypeScript 6.x, Vitest 4.x, and `ws` 8.x. It exposes `dist/index.js` as the package main and Pi extension entry, plus `remote-pi` and `pi-supervisord` binaries. The scripts define the standard development cycle: `build` runs `tsc`, `typecheck` runs `tsc --noEmit`, `dev` runs `tsx src/index.ts`, `test` runs `vitest run`, and `prepublishOnly` chains typecheck/test/build.

## Key passages

- Package fields: `"type": "module"`, `"main": "dist/index.js"`, `"types": "dist/index.d.ts"`, and Pi extension metadata pointing at `./dist`.
- Engine: `"node": ">=20.0.0"`.
- Scripts: `build`, `typecheck`, `dev`, `test`, and `prepublishOnly` map to TypeScript/Vitest commands.
- Dependencies include `@earendil-works/pi-coding-agent`, `ws`, `@noble/ed25519`, `@napi-rs/keyring`, `zod`, and `typebox`.
- Dev dependencies include `typescript`, `vitest`, `tsx`, `@types/node`, and `@types/ws`.

## Structural metadata

- Source type: package manifest
- Path: `/home/agent/projects/remote_pi/pi-extension/package.json`
