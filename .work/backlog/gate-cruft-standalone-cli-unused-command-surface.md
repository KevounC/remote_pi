---
id: gate-cruft-standalone-cli-unused-command-surface
kind: story
stage: drafting
tags: [cleanup]
parent: null
depends_on: []
release_binding: null
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-01
---

# Remove unused standalone CLI command-surface dependency

## Confidence
Medium

## Category
unused parameter / defensive seam

## Location
`pi-extension/src/extension/command_surface/standalone_cli.ts:41`

## Evidence
```ts
export interface StandaloneCliAdapterDeps {
  readonly commandSurface: RemotePiCommandSurfaceHarness;
  readonly listPeers: () => Promise<StoredPeer[]>;
  readonly removePeer: (remoteEpk: string) => Promise<boolean>;
```

```ts
  // The harness is part of the CLI bootstrap contract: index.ts passes the same
  // command-surface test seam used by compatibility exports, so future CLI
  // commands can route through that stable seam without re-opening index.ts.
  void input.commandSurface;
```

## Removal
Either make standalone CLI commands use `input.commandSurface` for the paths it was meant to route, or remove the dependency and the `void input.commandSurface` suppression until a real consumer exists.
