---
id: remote-pi-mobile-working-status-stuck
created: 2026-06-27
updated: 2026-06-27
tags: [pi-extension, app, bug]
---

Remote-pi mobile session status can remain stuck on `Working` even when the workstation/Pi agent is idle and not taking a turn.

Context from live private-fork smoke after the stale-context and local-display fixes:
- Mobile messages now get in/out and render in the workstation session.
- The main stale-context path appears fixed.
- New oddity observed: the mobile app still shows `Working` while the agent is idle.

Likely areas to inspect later:
- `room_meta.working` publication in the Pi extension (`turn_start`, `turn_end`, compaction hooks, reconnect room meta).
- App-side handling/debouncing of `room_meta_update` and reconnect hydration.
- Whether a dropped `turn_end` or reconnect replay leaves stale `working: true` in cached room metadata.
