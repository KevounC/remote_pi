---
id: gate-docs-readme-stale-boilerplate
kind: story
stage: drafting
tags: [documentation]
parent: null
depends_on: []
release_binding: cockpit-v1.6.0
gate_origin: docs
created: 2026-07-01
updated: 2026-07-01
---

# Cockpit README is stale/boilerplate and not project-specific

## Location
cockpit/README.md:1-17

## Issue
README content is still generic Flutter starter text and no longer reflects Cockpit's local usage, run/build conventions, or features.

## Recommendation
Replace with an operator-facing Cockpit README (project purpose, setup/build/run, remote-pi control surface, key commands, and links to canonical docs).
