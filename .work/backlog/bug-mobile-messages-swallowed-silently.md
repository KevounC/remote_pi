---
id: bug-mobile-messages-swallowed-silently
created: 2026-06-28
updated: 2026-06-28
tags: [bug, app, pi-extension]
---

Mobile messages are getting swallowed silently on the current remote sessions.

Context from operator report: messages sent from the mobile surface appear to disappear without an obvious error or recovery signal. Investigate the app → relay → pi-extension send/echo path and any silent-drop behavior before assuming this is only a UI issue.
