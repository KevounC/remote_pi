---
id: story-fix-room-switch-snapshot-adoption
kind: story
stage: implementing
tags: [app, bug]
parent: epic-remote-session-resilience-refactor
depends_on: [feature-adversarial-codebase-review]
release_binding: null
gate_origin: null
created: 2026-06-28
updated: 2026-06-28
---

# Prevent room snapshots from undoing explicit same-peer room switches

Adversarial review found `_maybeAdoptLegacyRoom` can treat a legitimate same-peer room switch as legacy room discovery and reset outbound routing to the first room in a later snapshot.

## Scope

- Distinguish legacy discovery for peers without a persisted room from explicit user room switches.
- Ensure snapshots refresh metadata without changing `_activeRoomId` after `switchRoom()`.

## Acceptance Criteria

- [ ] Switching to a second room on the same peer survives a later `RoomsSnapshot` whose first room is `main`.
- [ ] Legacy peers with no persisted room still adopt the discovered room once.
- [ ] Add `ConnectionManager` tests for both cases.
