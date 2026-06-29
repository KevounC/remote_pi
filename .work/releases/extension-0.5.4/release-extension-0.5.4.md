---
id: release-extension-0.5.4
kind: release
stage: released
tags: [pi-extension]
parent: null
depends_on: []
release_binding: extension-0.5.4
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Release extension-0.5.4

pi-extension patch over `extension-0.5.3`. Captures the stale-context /
session-bound / peers.json hardening fixes shipped before the bold-refactor arc
began.

## Bound items

8 items (all `stage: done`, bound by the pi-extension-component attribution rule):

- `story-stale-session-bound-surface-deep-audit`
- `story-fix-session-start-message-api-recapture`
- `story-remote-pi-local-vendor-switch`
- `story-remote-pi-stale-context-source-fix`
- `story-fix-stale-pi-api-after-app-session-new`
- `story-remote-pi-stale-context-investigation`
- `story-harden-peers-json-permissions`
- `story-stale-extension-runtime-audit`

## Gate runs

None — `gates_for_release: []`.

## Shipped items

Bodies live on disk (`retain-bodies`). Active done items moved to
`.work/releases/extension-0.5.4/`.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| story-stale-session-bound-surface-deep-audit | Stale session-bound surface deep audit | story | — | HEAD |
| story-fix-session-start-message-api-recapture | Session start message API recapture | story | — | HEAD |
| story-remote-pi-local-vendor-switch | Local vendor switch | story | — | HEAD |
| story-remote-pi-stale-context-source-fix | Stale context source fix | story | — | HEAD |
| story-fix-stale-pi-api-after-app-session-new | Stale Pi API after app session new | story | — | HEAD |
| story-remote-pi-stale-context-investigation | Stale context investigation | story | — | HEAD |
| story-harden-peers-json-permissions | Harden peers.json permissions | story | — | HEAD |
| story-stale-extension-runtime-audit | Stale extension runtime audit | story | — | HEAD |

## Notes

- Date shipped: 2026-06-29 (substrate catch-up)
- Mapping: `tag-based`
- Total items shipped: 8
- Gate finding totals: n/a
