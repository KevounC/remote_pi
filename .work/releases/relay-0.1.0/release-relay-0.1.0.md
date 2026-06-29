---
id: release-relay-0.1.0
kind: release
stage: released
tags: [relay]
parent: null
depends_on: []
release_binding: relay-0.1.0
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Release relay-0.1.0

First relay release. The relay had no prior tag; `0.1.0` reflects that this is
its first tracked release despite the relay code existing since project
inception. Captures the mesh-auth-cache reverify and control-frame-fanout cap.

## Bound items

2 items (all `stage: done`, bound by the relay-component attribution rule):

- `story-reverify-relay-mesh-auth-cache`
- `story-cap-relay-control-frame-fanout`

## Gate runs

None — `gates_for_release: []`.

## Shipped items

Bodies live on disk (`retain-bodies`). Active done items moved to
`.work/releases/relay-0.1.0/`.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| story-reverify-relay-mesh-auth-cache | Reverify relay mesh auth cache | story | — | HEAD |
| story-cap-relay-control-frame-fanout | Cap relay control frame fanout | story | — | HEAD |

## Notes

- Date shipped: 2026-06-29 (substrate catch-up)
- Mapping: `tag-based`
- Total items shipped: 2
- Gate finding totals: n/a
