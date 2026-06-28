---
id: story-remote-pi-mobile-mode-client-slice
kind: story
stage: drafting
tags: [app, pi-extension, workflow]
parent: feature-remote-pi-fork-vendor-and-mobile-surface
depends_on: [story-remote-pi-android-build-smoke]
created: 2026-06-27
updated: 2026-06-27
---

# Add one remote-pi client-side mobile-mode control slice

## Brief

Only after the SNC-root plain-text `story-pi-mobile-mode-toggle` path and local Android build path are known,
add a minimal in-app control for mobile mode if real use shows text controls are insufficient.

## Candidate slice

Add a Quick Action or lightweight input affordance that sends the same semantic control as the
plain-text extension path (`mobile on`, `mobile off`, `mobile status`) without requiring slash-command
support.

## Acceptance

- The in-app control toggles mobile mode in the paired Pi session.
- It does not require broad protocol redesign.
- The implementation records whether the right upstream path is a PR to `remote-pi` or a private fork carry.
