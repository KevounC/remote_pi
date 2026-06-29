---
id: release-app-v1.1.1
kind: release
stage: released
tags: [app]
parent: null
depends_on: []
release_binding: app-v1.1.1
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Release app-v1.1.1

Mobile app patch over `app-v1.1.0`. Captures the mobile-side fixes shipped to
the operator's phone before the bold-refactor arc began — kept separate from
refactor work per operator direction.

## Bound items

8 items (all `stage: done`, bound by the app-component attribution rule):

- `story-fix-mobile-message-send-failures-visible`
- `story-preserve-pending-send-backstop-on-disconnect`
- `story-fix-mobile-working-convergence-on-disconnect`
- `story-make-pending-backstop-disconnect-test-deterministic`
- `story-fix-room-switch-snapshot-adoption`
- `story-remote-pi-android-build-smoke`
- `story-guard-history-clear-without-prior-start`
- `story-close-rooms-controller-on-dispose`

## Gate runs

None — `gates_for_release: []` for this fork (ships to operator's phone without
a gate process today).

## Shipped items

Bodies live on disk (`retain-bodies`). Archived items stay in `.work/archive/`;
active done items moved to `.work/releases/app-v1.1.1/`.

| id | title | kind | archived_atop | git ref |
|----|-------|------|---------------|---------|
| story-fix-mobile-message-send-failures-visible | Mobile message send failures visible | story | unbound | 3dba904 |
| story-preserve-pending-send-backstop-on-disconnect | Preserve pending-send backstop on disconnect | story | unbound | 3dba904 |
| story-fix-mobile-working-convergence-on-disconnect | Mobile working convergence on disconnect | story | unbound | 3dba904 |
| story-make-pending-backstop-disconnect-test-deterministic | Make pending-backstop disconnect test deterministic | story | unbound | 3dba904 |
| story-fix-room-switch-snapshot-adoption | Room switch snapshot adoption | story | unbound | 3dba904 |
| story-remote-pi-android-build-smoke | Android build smoke | story | unbound | 3dba904 |
| story-guard-history-clear-without-prior-start | Guard history clear without prior start | story | unbound | 3dba904 |
| story-close-rooms-controller-on-dispose | Close rooms controller on dispose | story | unbound | 3dba904 |

## Notes

- Date shipped: 2026-06-29 (substrate catch-up; APK shipped to operator's phone earlier)
- Mapping: `tag-based` (local tag; push is external/operator-run)
- Total items shipped: 8
- Gate finding totals: n/a (no gates configured)
