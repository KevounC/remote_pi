---
id: idea-mobile-session-control
created: 2026-06-29
updated: 2026-06-29
tags: [app, pi-extension]
---

# Mobile app: session control and command surface gaps

Random thoughts from operator use of the mobile app.

## Bugs / gaps

- **"New Session" does not clear the chat log.** Tapping New Session starts a new
  pi session but the on-screen message history carries over, so the user can't
  tell they're in a fresh session and the transcript looks stale. The chat log
  should reset when a new session is created.
- **Slash commands are unusable from mobile.** There's no way to enter/discover
  slash commands (`/new`, `/help`, etc.) on the mobile keyboard surface. This
  blocks a lot of pi interaction that relies on slash commands.

## Feature requests

- **Spawn new pi sessions from mobile.** Beyond the existing New Session behavior,
  the mobile app should be able to actually launch new pi sessions on the remote
  box (not just switch between already-known sessions).
  - Stretch goal: let the user **pick a cwd** when spawning the new session, so a
    fresh session can start rooted in a chosen project directory rather than
    wherever the daemon/extension defaults.
