---
id: story-remote-pi-android-build-smoke
kind: story
stage: drafting
tags: [app]
parent: feature-remote-pi-fork-vendor-and-mobile-surface
depends_on: []
release_binding: null
gate_origin: null
created: 2026-06-27
updated: 2026-06-27
---

# Build and pair the forked remote-pi Android app locally

## Brief

Prove the forked `app/` can be built locally and paired with the existing relay/dev VM path before
planning client-side UX changes.

## Tasks

- Inspect Flutter/Android prerequisites in `/home/agent/forks/remote_pi/app`.
- Confirm whether this dev VM has Flutter/Android SDK tooling; if not, record the workstation-only
  steps rather than forcing install in this environment.
- Build a debug APK if tooling is available.
- Pair the built app against the existing relay and a local Pi session.
- Record any signing, package-id, or license blockers before distribution beyond private/dev use.

## Acceptance

- A local build path is documented.
- Either a debug APK is built and paired, or blockers are explicit and actionable.
- The item records whether app work can proceed on this VM or requires workstation/Android tooling.
