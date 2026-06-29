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
- **New messages don't auto-scroll the chat to the bottom.** When a new message
  arrives (or is sent), the chat window stays at its current scroll position
  instead of scrolling down to show the latest message, so the user has to
  manually scroll to follow the conversation.

## UX/UI polish

- **No feedback when tool calls are hidden.** With tool calls collapsed/hidden in
  the chat, it's not obvious whether a sent message has actually gone through or
  whether the agent is still thinking. There's no clear "thinking / working"
  vs "idle / waiting" indicator tied to the current message state, so the user
  can't tell if they should wait or re-send.
- **Missing terminal-style status info.** The mobile chat has none of the
  terminal UX pi normally surfaces — no context window % used, no token counts,
  no cost/usage feedback. Bringing some of that status telemetry onto the mobile
  surface would help users gauge session health and when to start a new session.

## Feature requests

- **Spawn new pi sessions from mobile.** Beyond the existing New Session behavior,
  the mobile app should be able to actually launch new pi sessions on the remote
  box (not just switch between already-known sessions).
  - Stretch goal: let the user **pick a cwd** when spawning the new session, so a
    fresh session can start rooted in a chosen project directory rather than
    wherever the daemon/extension defaults.
