---
id: gate-cruft-unused-command-surface-legacy-deps
kind: story
stage: implementing
tags: [cleanup]
parent: null
depends_on: []
release_binding: extension-0.6.0
gate_origin: cruft
created: 2026-07-01
updated: 2026-07-01
---

# Remove unused command-surface legacy deps seam

## Confidence
High

## Category
unused export / dead type

## Location
`pi-extension/src/extension/command_surface/legacy_deps.ts:5`

## Evidence
```ts
/**
 * Legacy command-surface seam for the incremental index split.
 *
 * The concrete factories still live in `index.ts` during step 1; this type
 * gives later command-surface extraction steps a stable import target without
 * pulling god-file globals into the pure command module.
 */
export type LegacyCommandSurfaceDeps = CommandSurfaceDeps & {
  readonly registerCommands: (pi: ExtensionAPI) => void;
};
```

`grep` over `pi-extension/src/**/*.ts` found `LegacyCommandSurfaceDeps` only in this file and in the unrelated `extension/legacy_ports.ts` interface; no source imports `extension/command_surface/legacy_deps.ts`.

## Removal
Delete `pi-extension/src/extension/command_surface/legacy_deps.ts` if no package-level export depends on it. If the type was intended to survive, wire it to an actual command-surface consumer and update the stale “during step 1” comment so it no longer reads like an abandoned split artifact.
