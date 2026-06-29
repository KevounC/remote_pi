---
id: epic-bold-canonical-session-app-attribution-hydration
kind: feature
stage: drafting
tags: [refactor, bold, app, security]
parent: epic-bold-canonical-session
depends_on: [epic-bold-canonical-session-wire-discriminator]
release_binding: null
gate_origin: null
created: 2026-06-29
updated: 2026-06-29
---

# Canonical session — app attribution & hydration fail-closed

## Brief
The app half of the contamination fix. Require `session_id` on every
chat-bearing ServerMessage; drop + log when absent or mismatched. Retire the
"legacy no-room routes unconditionally" path in `ws_transport.dart`. `_onServerMessage`
validates the embedded `session_id` against the active session before accepting.
`_applyHistory` refuses a `session_history` whose `session_id` != active session
— so a foreign history can never replace the local transcript box (the direct
fix for "session B showed only session A's stray turn"). Lift room/session demux
from transport-optimization to correctness boundary.

## Epic context
- Parent epic: `epic-bold-canonical-session`
- Position: consumer of the wire discriminator (the `session_id` field) and
  precondition for the transcript-event-log epic's replay-as-projection.

## Foundation references
- Evidence: `app/lib/data/transport/ws_transport.dart:63-103`,
  `app/lib/data/sync/sync_service.dart:409-435` (epk-only gate),
  `:497-535` (active-box write), `:671-760` (`_applyHistory` replaces).

<!-- /agile-workflow:refactor-design pins the validation sites + failure
semantics. -->
