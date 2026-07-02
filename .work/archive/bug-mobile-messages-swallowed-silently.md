---
id: bug-mobile-messages-swallowed-silently
kind: story
stage: done
tags: [bug, app, pi-extension]
parent: null
depends_on: []
release_binding: v0.6.0
gate_origin: null
archived_atop: unbound
archived_ref: 3dba904
status: superseded
resolved_by: story-fix-mobile-message-send-failures-visible
created: 2026-06-28
updated: 2026-07-01
---

> **SUPERSEDED 2026-06-29** — resolved by `story-fix-mobile-message-send-failures-visible`
> (archived in `.work/archive/`). Silent mobile send drops now surface a visible
> chat error and the stale-extension-ctx rejection path was hardened by the
> `story-remote-pi-stale-context-source-fix` family. Kept for historical context.

Mobile messages are getting swallowed silently on the current remote sessions.

Context from operator report: messages sent from the mobile surface appear to disappear without an obvious error or recovery signal. Investigate the app → relay → pi-extension send/echo path and any silent-drop behavior before assuming this is only a UI issue.

Additional live symptom captured from current remote sessions:

- Mobile side showed `internal_error: Agent rejected incoming message: This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload(). For newSession, fork, and switchSession, move post-replacement work into withSession and use the ctx passed to withSession. For reload, do not use the old ctx after await ctx.reload().`
- Workstation side logged `[remote-pi] app user_message id=cli_019f10be-853e-7a4f-a231-131b629a2cb2: agent rejected incoming message: This extension ctx is stale after session replacement or reload...` and then `Error: [remote-pi] failed to process incoming message: This extension ctx is stale after session replacement or reload...`.

This suggests at least one swallowed/rejected mobile send path may still be using a stale captured Pi or command context after session replacement/reload. Cross-check against existing stale-context follow-up stories before scoping a new fix.

Promoted follow-up: `story-fix-mobile-message-send-failures-visible` covers the app-side silent send/no-echo failure surface so missing echoes or send errors render a visible chat error instead of disappearing.
