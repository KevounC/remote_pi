---
id: feature-remote-pi-fork-vendor-and-mobile-surface
kind: feature
stage: drafting
tags: [pi-extension, app, workflow]
parent: epic-remote-session-resilience-refactor
depends_on: []
created: 2026-06-27
updated: 2026-06-27
---

# Remote-pi fork, local vendor switch, and mobile-surface development

## Brief

Revived after the 2026-06-27 `remote-pi` stale-context crash while reconnecting to a Pi session.
The immediate local hotfix was made against the installed npm package, which is not durable across
`remote-pi` updates. Scope the fork/vendor path first, then implement in small slices.

## Current state

- GitHub upstream: `jacobaraujo7/remote_pi`.
- Operator fork: `KevounC/remote_pi`.
- Local clone: `/home/agent/forks/remote_pi`.
- Clone remotes:
  - `origin` → `https://github.com/KevounC/remote_pi.git`
  - `upstream` → `https://github.com/jacobaraujo7/remote_pi.git` with push URL disabled.
- Repo layout:
  - `app/` — Flutter mobile client (Android/iOS)
  - `pi-extension/` — Node/TypeScript Pi extension
  - `relay/` — Rust WebSocket relay
  - `cockpit/`, `site/`, support services
- License first pass: `pi-extension` is MIT. Repo README says licensing is per-package and a
  repository-wide license decision is pending; no obvious `app/` license file was found. Treat app
  binary distribution as private/dev-only until license posture is clarified.
- Fork implementation status: the local vendor switch and stale-context source fix have been completed
  and recorded in child stories; remaining fork-local work is app build/pairing smoke and any client slices.

## Motivation

The current `remote-pi` mobile path is workable but now has two separate needs:

1. **Durable extension patch lane.** Local patches to `~/.pi/agent/npm/node_modules/remote-pi` are
   fragile. We need a local fork/vendor workflow that Pi can load during development.
2. **Future client/control affordances.** Slash-command invocation is not available/ergonomic from
   the app, and mobile operation likely benefits from first-class controls for mobile mode, session
   lifecycle, queued work, and notifications.

## Child work

- [`story-remote-pi-local-vendor-switch`](../stories/story-remote-pi-local-vendor-switch.md) — switch
  Pi development loading from the npm package to the local fork without losing the ability to revert.
- [`story-remote-pi-stale-context-investigation`](../stories/story-remote-pi-stale-context-investigation.md)
  — pin the recurring stale-context rejection sequence and classify unsafe context captures before patching.
- [`story-remote-pi-stale-context-source-fix`](../stories/story-remote-pi-stale-context-source-fix.md)
  — port the stale-context crash fix into `pi-extension/src/`, verify, and prepare upstreamable patch.
- [`story-remote-pi-android-build-smoke`](../stories/story-remote-pi-android-build-smoke.md) — prove
  the Flutter app can build locally and pair against the current relay.
- [`story-remote-pi-mobile-mode-client-slice`](../stories/story-remote-pi-mobile-mode-client-slice.md)
  — only after the build path is known, add one thin in-app control slice if plain-text mobile mode
  is not enough.

## Acceptance

- The local fork checkout is documented and cleanly connected to upstream.
- Pi can be switched to load the forked extension for development, with a clear rollback to npm.
- The stale-context fix lives as source changes in the fork and passes `pi-extension` verification.
- The Android app build/pairing path is known, or blockers are recorded.
- Fork-vs-upstream-contribution recommendation is recorded before long-lived divergence.
