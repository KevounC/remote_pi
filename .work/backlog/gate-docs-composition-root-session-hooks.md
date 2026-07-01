---
id: gate-docs-composition-root-session-hooks
kind: story
stage: drafting
tags: [documentation]
parent: null
depends_on: []
release_binding: null
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# Pi extension lifecycle hooks were moved out of `src/index.ts`

## Drift category
repo-skill-staleness

## Location
- `.agents/skills/pi-extension-typescript/SKILL.md:97`
- `pi-extension/src/extension/composition_root.ts:55`, `pi-extension/src/extension/composition_root.ts:61`
- `pi-extension/src/index.ts:87`, `pi-extension/src/index.ts:1387`

## Current doc text
"Hooks actually used in `src/index.ts` include: ... `session_start` — capture the freshest session-bound context. ... `session_shutdown` — tear down stale outgoing instance."

## Reality
`src/index.ts` no longer registers `session_start`/`session_shutdown` directly. Those lifecycle hooks are implemented in `pi-extension/src/extension/composition_root.ts` (`pi.on("session_start"...)` and `pi.on("session_shutdown"...)`) and are wired from `index.ts` via `registerLifecycleHooks(...)`.

## Required edit
Update this section to avoid claiming the hooks live in `src/index.ts`; describe `composition_root.ts` as the lifecycle hook owner and keep `src/index.ts` documented as the composition entrypoint that invokes `registerLifecycleHooks` through the `RemotePiRuntimePorts` seam.