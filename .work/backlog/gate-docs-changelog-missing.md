---
id: gate-docs-changelog-missing
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

# Missing changelog entry for active release cockpit-v1.6.0

## Location
CHANGELOG.md:12 ; .work/active/release-cockpit-v1.6.0.md:14-19

## Issue
A quality-gate release bundle for cockpit-v1.6.0 exists and is marked with active bound items, but no matching release notes entry exists in CHANGELOG.md.

## Recommendation
Add a release section for cockpit-v1.6.0 with scope/fixes added (workspace projection, agent/session, settings split, cockpit control RPC, transcript hydration). NOTE: release-deploy Phase 5.5 drafts the changelog before ship; this gate finding confirms that step is pending.
