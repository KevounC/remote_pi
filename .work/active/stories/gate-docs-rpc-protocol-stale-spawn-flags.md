---
id: gate-docs-rpc-protocol-stale-spawn-flags
kind: story
stage: implementing
tags: [documentation]
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# rpc-protocol.md documents stale pi --mode rpc spawn flags and relay assumptions

## Location
cockpit/docs/rpc-protocol.md:9-11 ; cockpit/lib/app/core/env.dart:28-30,56-57

## Issue
The doc claims Cockpit spawns pi --mode rpc --no-session --no-extensions and is local-only without remote-pi. Actual spawn defaults are noSession=false and noExtensions=false, with extension support enabled (for remote-pi command discovery/control).

## Recommendation
Update the spawn contract section to match current defaults and explicitly document that extensions are intentionally loaded and relay/remote-pi control commands are supported via control overlay.
