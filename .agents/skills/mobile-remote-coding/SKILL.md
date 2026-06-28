---
name: mobile-remote-coding
description: Cross-cutting Remote Pi mobile remote-coding checklist. Read before changing app/pi-extension/relay behavior for long-lived remote sessions, mobile control surfaces, reconnect hydration, working/idle state, multi-client synchronization, or session replacement.
updated: 2026-06-28
---

# Mobile Remote-Coding Checklist

> Scope: cross-cutting `app/`, `pi-extension/`, and `relay/` behavior for a phone piloting long-lived Pi coding sessions.
> Read with: `.agents/skills/flutter-mobile/SKILL.md` for app work and `.agents/skills/pi-extension-typescript/SKILL.md` for extension work.

## Core posture

A mobile Remote Pi client is not a terminal with perfect continuity. Android can restrict background network work, and iOS can suspend the app so no process code runs and sockets may be reclaimed. [android-background-restrictions]{1} [apple-networking-multitasking]{1} Flutter lifecycle notifications help, but state notifications can be skipped; do not rely on receiving every lifecycle edge. [flutter-app-lifecycle]{1}

Design every remote-coding feature as:

```text
authoritative snapshot + idempotent commands + replayable deltas + reconnect hydration
```

Never design it as:

```text
sticky UI boolean + best-effort event stream + hope the phone stayed awake
```

## State model requirements

For every user-visible remote session, model at least these states distinctly:

- `connected idle` — relay reachable, room live, no active turn.
- `working` — authoritative room/session metadata says an agent turn or compaction is in progress.
- `reconnecting` — app is retrying or has a relay connection but no fresh room signal.
- `offline` — no usable relay connection or peer/room unavailable.
- `stale/unknown` — cached room exists but no current snapshot has confirmed it.
- `error/action failed` — user action was rejected or failed and needs an explicit recovery affordance.

Remote Pi already has the pieces: `ConnectionStatus`, canonical presence/room snapshot streams, `_roomsByPeer` vs `_liveRoomIds`, and `markRoomWorking` as the active-room correction path. [remote-pi-app-transport-state]{1}

## Snapshot and event rules

- On attach/reconnect/resume/session switch, request an authoritative snapshot before trusting cached UI state.
- Event deltas may update the UI optimistically, but a later snapshot must be able to correct them.
- Sequence, dedupe, or otherwise make deltas idempotent when adding new message families.
- Treat absence explicitly. If a field is absent in an open-ended metadata envelope, decide whether to preserve the old value or clear it; document that choice in code/tests.
- Do not leave boolean state sticky. Every `working: true` path needs false convergence for success, error, abort/cancel, disconnect/reconnect, and session replacement.

## Mobile lifecycle rules

- Use Flutter lifecycle listeners for resume/pause hooks, but treat them as hints. [flutter-app-lifecycle-listener]{1}
- On resume: reconnect if needed, replay subscriptions, request room/session snapshots, and reconcile visible state.
- On pause/background: avoid waiting on network. If a quick nonblocking quiesce is safe, send it best-effort; otherwise rely on resume hydration. Apple's networking note warns against waiting for network in background transition paths. [apple-networking-multitasking]{1}
- Do not promise background turn streaming unless the platform-specific background mode and notification behavior are deliberately implemented and tested.
- Long-running mobile-visible status should be recoverable from server/extension state after the app process is suspended or killed.

## Command semantics

Every app action should be safe under retry and late arrival:

- Include a stable action/message id.
- ACK only after the receiving side has accepted or explicitly rejected the command.
- Make retry either idempotent or visibly rejected as duplicate/stale.
- Bind actions to `(peer, room/session)` so a delayed response cannot mutate the currently selected session.
- For `/new` or session replacement, assume old app/extension contexts may still have delayed callbacks; route through fresh session context and clear stale handles. See the pi-extension stale-context guidance. [remote-pi-index-lifecycle]{1}

## UX expectations for phone operation

- The phone should always answer: “Which peer/room am I controlling?”, “Is it connected?”, “Is it working?”, and “What can I safely do next?”
- Tool approval, cancel, steer, `/new`, compaction, model/thinking changes, and queue edits must surface success/failure distinctly.
- Stale cached state should look stale, not live. A grey/stale room is better than a misleading green/working room.
- Multi-client changes should be visible: if another client starts a turn, switches model, or clears a session, the phone should hydrate or receive a broadcast rather than waiting for local action.

## Verification matrix

Before approving a cross-cutting remote-coding change, test or explicitly defer these cases:

- Fresh pair → first room appears without cold restart.
- Relay disconnect/reconnect while idle.
- Relay disconnect/reconnect while working.
- Pi session replacement (`session_new`, `/new`, `/resume`, or daemon restart) while app is attached.
- App background → foreground while idle and while working.
- Duplicate/delayed/out-of-order room metadata events.
- Snapshot after stale `working: true` corrects to false.
- Session switch while old stream still has late frames.
- Multiple clients attached to the same room.
- Cancel/abort/error path clears active working state.

Use deterministic state-machine tests where possible and one manual phone/Android build smoke for UI lifecycle changes.

## Anti-patterns

- Relying on mobile background WebSocket continuity for correctness.
- Treating event delivery as exactly-once.
- Updating only the local visible room when a relay/extension broadcast affects multiple rooms.
- Letting `/new` or compaction acknowledge before the app can discover the replacement session's true state.
- Rendering an optimistic status without a timeout, ACK, or snapshot correction path.
- Confusing human clients with agent-network mesh peers; mesh peers are coding-agent endpoints, not phone/workstation presence.
