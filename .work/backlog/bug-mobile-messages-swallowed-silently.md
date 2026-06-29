---
id: bug-mobile-messages-swallowed-silently
created: 2026-06-28
updated: 2026-06-28
tags: [bug, app, pi-extension]
---

Mobile messages are getting swallowed silently on the current remote sessions.

Context from operator report: messages sent from the mobile surface appear to disappear without an obvious error or recovery signal. Investigate the app → relay → pi-extension send/echo path and any silent-drop behavior before assuming this is only a UI issue.

Additional live symptom captured from current remote sessions:

- Mobile side showed `internal_error: Agent rejected incoming message: This extension ctx is stale after session replacement or reload. Do not use a captured pi or command ctx after ctx.newSession(), ctx.fork(), ctx.switchSession(), or ctx.reload(). For newSession, fork, and switchSession, move post-replacement work into withSession and use the ctx passed to withSession. For reload, do not use the old ctx after await ctx.reload().`
- Workstation side logged `[remote-pi] app user_message id=cli_019f10be-853e-7a4f-a231-131b629a2cb2: agent rejected incoming message: This extension ctx is stale after session replacement or reload...` and then `Error: [remote-pi] failed to process incoming message: This extension ctx is stale after session replacement or reload...`.

This suggests at least one swallowed/rejected mobile send path may still be using a stale captured Pi or command context after session replacement/reload. Cross-check against existing stale-context follow-up stories before scoping a new fix.
